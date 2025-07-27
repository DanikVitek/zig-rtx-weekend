const std = @import("std");

const Vec3 = @import("Vec3.zig");
const Color = @import("Color.zig");

const objects = @import("objects.zig");
const Sphere = objects.Sphere;
const camera = @import("camera.zig");

pub fn main() !void {
    const world = .{
        Sphere.init(.init(.{ 0, 0, -1 }), 0.5),
        Sphere.init(.init(.{ 0, -100.5, -1 }), 100),
    };
    try camera.render(world);
}
