// -------------------------------------------------------------------------- //
// Copyright (c) 2019-2020, Jairus Martin.                                    //
// Distributed under the terms of the MIT License.                            //
// The full license is in the file LICENSE, distributed with this software.   //
// -------------------------------------------------------------------------- //
const std = @import("std");
const zhp = @import("zhp");
const web = zhp.web;

pub const io_mode = .evented;

const MainHandler = struct {
    handler: web.RequestHandler,

    pub fn get(self: *MainHandler, request: *web.Request,
               response: *web.Response) !void {
        try response.headers.append("Content-Type", "text/plain");
        try response.stream.writeAll("Hello, World!");
    }

};

const StreamHandler = struct {
    handler: web.RequestHandler,
    const template = @embedFile("templates/stream.html");

    // Dump a random stream of crap
    pub fn get(self: *StreamHandler, request: *web.Request,
               response: *web.Response) !void {
        if (std.mem.eql(u8, request.path, "/stream/live/")) {
            try response.headers.append("Content-Type", "audio/mpeg");
            try response.headers.append("Cache-Control", "no-cache");
            response.send_stream = true;
        } else {
            try response.stream.writeAll(template);
        }
    }

    pub fn stream(self: *StreamHandler, io: *web.IOStream) !usize {
        std.log.info("Starting audio stream", .{});
        const n = self.forward(io) catch |err| {
            std.log.info("Error streaming: {}", .{err});
            return 0;
        };
        return n;
    }

    pub fn forward(self: *StreamHandler, io: *web.IOStream) !usize {
        const writer = io.writer();
        const a = self.handler.response.allocator;
        // http://streams.sevenfm.nl/live

        std.log.info("Connecting...", .{});
        const conn = try std.net.tcpConnectToHost(a, "streams.sevenfm.nl", 80);
        defer conn.close();
        std.log.info("Connected!", .{});
        try conn.writeAll(
            "GET /live HTTP/1.1\r\n" ++
            "Host: streams.sevenfm.nl\r\n" ++
            "Accept: */*\r\n" ++
            "Connection: keep-alive\r\n" ++
            "\r\n");

        var buf: [4096]u8 = undefined;
        var total_sent: usize = 0;

        // On the first response skip their server's headers
        // but include the icecast stream headers from their response
        const end = try conn.read(buf[0..]);
        std.log.info("{}\n", .{buf[0..end]});

        const offset = if (std.mem.indexOf(u8, buf[0..end], "icy-br:")) |o| o else 0;
        try writer.writeAll(buf[offset..end]);
        total_sent += end-offset;

        // Now just forward the stream data
        while (true) {
            const n = try conn.read(buf[0..]);
            if (n == 0) {
                std.log.info("Stream disconnected", .{});
                break;
            }
            total_sent += n;
            try writer.writeAll(buf[0..n]);
            try io.flush(); // Send it out the pipe
        }
        return total_sent;
    }

};


const TemplateHandler = struct {
    handler: web.RequestHandler,
    const template = @embedFile("templates/cover.html");

    pub fn get(self: *TemplateHandler, request: *web.Request,
               response: *web.Response) !void {
        @setEvalBranchQuota(100000);
        try response.stream.print(template, .{"ZHP"});
    }

};

const JsonHandler = struct {
    handler: web.RequestHandler,

    pub fn get(self: *JsonHandler, request: *web.Request,
               response: *web.Response) !void {
        try response.headers.append("Content-Type", "application/json");

        var jw = std.json.writeStream(response.stream, 4);
        try jw.beginObject();
        for (request.headers.headers.items) |h| {
            try jw.objectField(h.key);
            try jw.emitString(h.value);
        }
        try jw.endObject();
    }

};

const ErrorTestHandler = struct {
    handler: web.RequestHandler,

    pub fn get(self: *ErrorTestHandler, request: *web.Request,
               response: *web.Response) !void {
        try response.stream.writeAll("Do some work");
        return error.Ooops;
    }

};


const FormHandler = struct {
    handler: web.RequestHandler,

    pub fn get(self: *FormHandler, request: *web.Request,
               response: *web.Response) !void {
        try response.stream.writeAll(
            \\<form action="/form/" method="post" enctype="multipart/form-data">
            \\<input type="text" name="name" value="Your name"><br />
            \\<input type="checkbox" name="agree" /><label>Do you like Zig?</label><br />
            \\<input type="file" name="image" /><label>Upload</label><br />
            \\<button type="submit">Submit</button>
            \\</form>
        );
    }

    pub fn post(self: *FormHandler, request: *web.Request,
               response: *web.Response) !void {
        var content_type = request.headers.get("Content-Type") catch |err| switch (err) {
            error.KeyError => "",
            else => return err,
        };
        if (std.mem.startsWith(u8, content_type, "multipart/form-data")) {
            var form = web.forms.Form.init(response.allocator);
            try form.parse(request);
            try response.stream.print(
                \\<h1>Hello: {}</h1>
                , .{if (form.fields.get("name")) |name| name else ""}
            );

            if (form.fields.get("agree")) |f| {
                try response.stream.writeAll("Me too!");
            } else {
                try response.stream.writeAll("Aww sorry!");
            }

            try response.stream.print(
                \\<h1>Request: {}</h1>
                , .{request.body});
        } else {
            response.status = web.responses.BAD_REQUEST;
            try response.stream.writeAll("<h1>BAD REQUEST</h1>");
            return;
        }
    }
};


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const allocator = &gpa.allocator;

    const routes = &[_]web.Route{
        web.Route.create("cover", "/", TemplateHandler),
        web.Route.create("hello", "/hello", MainHandler),
        web.Route.create("json", "/json/", JsonHandler),
        web.Route.create("stream", "/stream/", StreamHandler),
        web.Route.create("stream-media", "/stream/live/", StreamHandler),
        web.Route.create("error", "/500/", ErrorTestHandler),
        web.Route.create("form", "/form/", FormHandler),
        web.Route.static("static", "/static/"),
    };

    var app = web.Application.init(.{
        .allocator=allocator,
        .routes=routes[0..],
        .debug=true,
    });

    // Logger
    var logger = zhp.middleware.LoggingMiddleware{};

    // Uncomment this if benchmarking
    try app.middleware.append(&logger.middleware);

    defer app.deinit();
    try app.listen("0.0.0.0", 5000);
    try app.start();
}
