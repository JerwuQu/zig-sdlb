const std = @import("std");
const c = @import("./c.zig").c;

const SAMPLE_RATE = 48000;
const CHANNELS = 2;
const BIT_DEPTH = 16;
const DEVICE_SAMPLES = 1024; // high enough not to crackle, low enough to not have much delay

pub const OpusFile = struct {
    pub const Error = error{
        OpenMemoryFailed,
        ReadFailed,
        EndOfFile,
    };

    of: *c.OggOpusFile,

    fn load(data: []const u8) Error!OpusFile {
        var err: c_int = undefined;
        var of: *c.OggOpusFile = c.op_open_memory(data.ptr, data.len, &err).?;
        if (err != 0) {
            return Error.OpenMemoryFailed;
        }
        errdefer c.op_free(of);
        return OpusFile{ .of = of };
    }
    fn deinit(self: *OpusFile) void {
        c.op_free(self.of);
    }
    fn decode(self: *OpusFile, buf: []f32, count: usize) Error!usize {
        const ret = c.op_read_float_stereo(self.of, buf.ptr, @intCast(c_int, count));
        if (ret < 0) {
            return Error.ReadFailed;
        } else if (ret == 0) {
            return Error.EndOfFile;
        }
        return @intCast(usize, ret) * CHANNELS;
    }
    fn rewind(self: *OpusFile) void {
        _ = c.op_pcm_seek(self.of, 0);
    }
};

pub const AudioDevice = struct {
    pub const Error = error{
        DeviceOpenFailed,
    };

    pub const PlayHandle = usize;
    pub const PlayOptions = struct {
        volume: f32 = 1.0,
        loop: bool = false,
    };

    const PlayBuffer = struct {
        file: OpusFile,
        opt: PlayOptions,
        deletePending: bool = false,
        sampleDelay: usize = 0, // skip N samples

        /// Will arithmetically add samples to the output buffer
        pub fn addSamples(self: *PlayBuffer, bufOut: []f32) !void {
            var buf: [DEVICE_SAMPLES * CHANNELS]f32 = undefined;

            var writtenI: usize = std.math.min(buf.len, self.sampleDelay);
            self.sampleDelay -= writtenI;
            while (writtenI != bufOut.len) {
                // Decode
                const want = std.math.min(buf.len, bufOut.len - writtenI);
                const got = self.file.decode(&buf, want) catch |e| {
                    if (e == OpusFile.Error.EndOfFile) {
                        if (self.opt.loop) {
                            self.file.rewind();
                        } else {
                            self.deletePending = true;
                            self.file.deinit();
                        }
                        return;
                    }
                    return e;
                };

                // Apply volume and add
                var i: usize = 0;
                while (i < got) : (i += 1) {
                    bufOut[writtenI + i] += buf[i] * self.opt.volume;
                }
                writtenI += got;
            }
        }
    };

    const PlayBufferMap = std.AutoHashMap(PlayHandle, PlayBuffer);

    alloc: *std.mem.Allocator,
    playbackIncrement: usize = 0,
    device: c.SDL_AudioDeviceID,
    sounds: PlayBufferMap,
    lastSampleCallTick: u32,

    pub fn openDefault(alloc: *std.mem.Allocator) (Error || std.mem.Allocator.Error)!*AudioDevice {
        var audioDevice = try alloc.create(AudioDevice);
        audioDevice.alloc = alloc;
        audioDevice.playbackIncrement = 0;
        audioDevice.sounds = PlayBufferMap.init(alloc);
        audioDevice.lastSampleCallTick = c.SDL_GetTicks();

        const audioSpec = c.SDL_AudioSpec{
            .freq = SAMPLE_RATE,
            .format = c.AUDIO_F32,
            .channels = CHANNELS,
            .samples = DEVICE_SAMPLES,
            .userdata = audioDevice,
            .callback = sdlAudioCallback,
            .silence = 0,
            .size = 0,
            .padding = 0,
        };
        audioDevice.device = c.SDL_OpenAudioDevice(null, 0, &audioSpec, null, 0);
        if (audioDevice.device == 0) {
            return Error.DeviceOpenFailed;
        }
        c.SDL_PauseAudioDevice(audioDevice.device, 0);
        return audioDevice;
    }
    pub fn deinit(self: *AudioDevice) void {
        c.SDL_PauseAudioDevice(self.device, 0);
        c.SDL_CloseAudioDevice(self.device);
        self.sounds.deinit();
        self.alloc.destroy(self);
    }
    pub fn play(self: *AudioDevice, filedata: []const u8, options: PlayOptions) !PlayHandle {
        const sampleDelay = @divTrunc((c.SDL_GetTicks() - self.lastSampleCallTick) * SAMPLE_RATE * CHANNELS, 1000);
        var file = try OpusFile.load(filedata);
        self.playbackIncrement += 1;
        c.SDL_LockAudioDevice(self.device);
        try self.sounds.put(self.playbackIncrement, PlayBuffer{
            .file = file,
            .opt = options,
            .sampleDelay = sampleDelay,
        });
        c.SDL_UnlockAudioDevice(self.device);
        return self.playbackIncrement;
    }
    pub fn stop(self: *AudioDevice, handle: PlayHandle) void {
        c.SDL_LockAudioDevice(self.device);
        var s = self.sounds.get(handle);
        if (s != null) {
            s.file.deinit();
            self.sounds.remove(handle);
        }
        c.SDL_UnlockAudioDevice(self.device);
    }
    // https://wiki.libsdl.org/SDL_AudioSpec#remarks
    fn sdlAudioCallback(userdata: ?*c_void, stream: [*c]u8, len: c_int) callconv(.C) void {
        const self = @ptrCast(*AudioDevice, @alignCast(@alignOf(*AudioDevice), userdata.?));
        var buf = @ptrCast([*c]f32, @alignCast(@alignOf(f32), stream))[0..@intCast(usize, @divTrunc(len, 4))];
        self.lastSampleCallTick = c.SDL_GetTicks();

        // Mix
        std.mem.set(f32, buf, 0);
        var soundIter = self.sounds.iterator();
        while (soundIter.next()) |kv| {
            kv.value_ptr.addSamples(buf) catch continue;
            if (kv.value_ptr.deletePending) {
                _ = self.sounds.remove(kv.key_ptr.*);
            }
        }
    }
};
