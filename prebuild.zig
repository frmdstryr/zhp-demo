const std = @import("std");

pub fn main() !void {
    const dest_folder = "zig-packages";

    try run(&[_][]const u8{
        "wget", "https://github.com/frmdstryr/zhp/archive/master.zip", "-O",
        "zhp.zip"});
    try run(&[_][]const u8{"unzip", "zhp.zip", "-d", dest_folder});
    try run(&[_][]const u8{"rm", "zhp.zip"});
}


pub fn run(cmd: [][]const u8) !void {
    var process = try std.ChildProcess.init(cmd, std.heap.page_allocator);
    try process.spawn();
    _ = try process.wait();
}
