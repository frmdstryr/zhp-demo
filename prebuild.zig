const std = @import("std");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    const dest_folder = "zig-packages";
    defer std.debug.assert(!gpa.deinit());

    try run(.{"wget", "https://github.com/frmdstryr/zhp/archive/master.zip", "-O", "zhp.zip"});
    try run(.{"unzip", "zhp.zip", "-d", dest_folder});
    try run(.{"rm", "zhp.zip"});
}


pub fn run(args: anytype) !void {
    var cmd: [args.len][]const u8 = undefined;
    inline for(args) |arg, i| {
        cmd[i] = arg;
    }
    var process = try std.ChildProcess.init(cmd[0..], std.heap.page_allocator);
    try process.spawn();
    _ = try process.wait();
}
