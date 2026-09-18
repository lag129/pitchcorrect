const std = @import("std");

pub const Error = error{
    InvalidWavFile,
    UnsupportedFormat,
};

pub const MonoPcm = struct {
    fs: i32,
    bits: i32,
    s: []f32,
};

const format_pcm: u16 = 1;
const format_extensible: u16 = 0xFFFE;

pub fn mono_wave_read(allocator: std.mem.Allocator, pcm: *MonoPcm, file_name: []const u8, io: std.Io) !void {
    var riff_chunk_id: [4]u8 = undefined;
    var riff_chunk_size: u32 = undefined;
    var riff_form_type: [4]u8 = undefined;
    var fmt_chunk_id: [4]u8 = undefined;
    var fmt_chunk_size: u32 = undefined;
    var fmt_wave_format_type: u16 = undefined;
    var fmt_channel: u16 = undefined;
    var fmt_samples_per_sec: u32 = undefined;
    var fmt_bytes_per_sec: u32 = undefined;
    var fmt_block_size: u16 = undefined;
    var fmt_bits_per_sample: u16 = undefined;
    var data_chunk_id: [4]u8 = undefined;
    var data_chunk_size: u32 = undefined;
    var data: i32 = undefined;
    var bytes: [3]u8 = undefined;

    const file = try std.Io.Dir.cwd().openFile(io, file_name, .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buf);
    const r = &file_reader.interface;

    try r.readSliceAll(&riff_chunk_id);
    riff_chunk_size = try r.takeInt(u32, .little);
    try r.readSliceAll(&riff_form_type);

    if (!std.mem.eql(u8, &riff_chunk_id, "RIFF") or !std.mem.eql(u8, &riff_form_type, "WAVE")) {
        return Error.InvalidWavFile;
    }

    while (true) {
        try r.readSliceAll(&fmt_chunk_id);
        fmt_chunk_size = try r.takeInt(u32, .little);
        if (std.mem.eql(u8, &fmt_chunk_id, "fmt ")) break;
        try r.discardAll(fmt_chunk_size + fmt_chunk_size % 2);
    }
    if (fmt_chunk_size < 16) return Error.InvalidWavFile;

    fmt_wave_format_type = try r.takeInt(u16, .little);
    fmt_channel = try r.takeInt(u16, .little);
    fmt_samples_per_sec = try r.takeInt(u32, .little);
    fmt_bytes_per_sec = try r.takeInt(u32, .little);
    fmt_block_size = try r.takeInt(u16, .little);
    fmt_bits_per_sample = try r.takeInt(u16, .little);

    var fmt_extra_size = fmt_chunk_size - 16;
    if (fmt_wave_format_type == format_extensible) {
        if (fmt_extra_size < 24) return Error.InvalidWavFile;
        try r.discardAll(8);
        fmt_wave_format_type = try r.takeInt(u16, .little);
        fmt_extra_size -= 10;
    }
    try r.discardAll(fmt_extra_size + fmt_chunk_size % 2);

    if (fmt_wave_format_type != format_pcm) return Error.UnsupportedFormat;
    if (fmt_channel == 0) return Error.InvalidWavFile;

    const bytes_per_sample: u32 = switch (fmt_bits_per_sample) {
        16 => 2,
        24 => 3,
        else => return Error.UnsupportedFormat,
    };

    while (true) {
        try r.readSliceAll(&data_chunk_id);
        data_chunk_size = try r.takeInt(u32, .little);
        if (std.mem.eql(u8, &data_chunk_id, "data")) break;
        try r.discardAll(data_chunk_size + data_chunk_size % 2);
    }

    pcm.fs = @intCast(fmt_samples_per_sec);
    pcm.bits = fmt_bits_per_sample;
    pcm.s = try allocator.alloc(f32, data_chunk_size / (bytes_per_sample * fmt_channel));
    errdefer allocator.free(pcm.s);

    const gain = 1.0 / @as(f32, @floatFromInt(fmt_channel));

    for (0..pcm.s.len) |n| {
        var sum: f32 = 0.0;

        for (0..fmt_channel) |_| {
            if (fmt_bits_per_sample == 16) {
                data = try r.takeInt(i16, .little);
                sum += @as(f32, @floatFromInt(data)) / 32768.0;
            } else {
                try r.readSliceAll(&bytes);
                data = (@as(i32, @as(i8, @bitCast(bytes[2]))) << 16) |
                    (@as(i32, bytes[1]) << 8) |
                    @as(i32, bytes[0]);
                sum += @as(f32, @floatFromInt(data)) / 8388608.0;
            }
        }

        pcm.s[n] = sum * gain;
    }
}

pub fn mono_wave_write(pcm: *MonoPcm, file_name: []const u8, io: std.Io) !void {
    const riff_chunk_id: [4]u8 = .{ 'R', 'I', 'F', 'F' };
    const riff_chunk_size: u32 = @intCast(36 + pcm.s.len * 2);
    const riff_form_type: [4]u8 = .{ 'W', 'A', 'V', 'E' };
    const fmt_chunk_id: [4]u8 = .{ 'f', 'm', 't', ' ' };
    const fmt_chunk_size: u32 = 16;
    const fmt_wave_format_type: u16 = format_pcm;
    const fmt_channel: u16 = 1;
    const fmt_samples_per_sec: u32 = @intCast(pcm.fs);
    const fmt_bits_per_sample: u16 = 16;
    const fmt_block_size: u16 = fmt_bits_per_sample / 8;
    const fmt_bytes_per_sec: u32 = fmt_samples_per_sec * fmt_block_size;
    const data_chunk_id: [4]u8 = .{ 'd', 'a', 't', 'a' };
    const data_chunk_size: u32 = @intCast(pcm.s.len * 2);
    var data: i16 = undefined;
    var s: f32 = undefined;

    const file = try std.Io.Dir.cwd().createFile(io, file_name, .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &buf);
    const w = &file_writer.interface;

    try w.writeAll(&riff_chunk_id);
    try w.writeInt(u32, riff_chunk_size, .little);
    try w.writeAll(&riff_form_type);
    try w.writeAll(&fmt_chunk_id);
    try w.writeInt(u32, fmt_chunk_size, .little);
    try w.writeInt(u16, fmt_wave_format_type, .little);
    try w.writeInt(u16, fmt_channel, .little);
    try w.writeInt(u32, fmt_samples_per_sec, .little);
    try w.writeInt(u32, fmt_bytes_per_sec, .little);
    try w.writeInt(u16, fmt_block_size, .little);
    try w.writeInt(u16, fmt_bits_per_sample, .little);
    try w.writeAll(&data_chunk_id);
    try w.writeInt(u32, data_chunk_size, .little);

    for (0..pcm.s.len) |n| {
        s = (pcm.s[n] + 1.0) / 2.0 * 65536.0;

        if (s > 65535.0) {
            s = 65535.0;
        } else if (s < 0.0) {
            s = 0.0;
        }

        data = @intCast(@as(i32, @intFromFloat(s + 0.5)) - 32768);
        try w.writeInt(i16, data, .little);
    }

    try w.flush();
}
