const std = @import("std");

const Vec3 = @import("Vec3.zig");
const Color = @import("Color.zig");

const objects = @import("objects.zig");
const Sphere = objects.Sphere;
const camera = @import("camera.zig");

pub fn main() !void {
    const world = .{
        Sphere.init(
            .init(.{ 0, -100.5, -1 }),
            100,
            .{ .lambertian = .{ .albedo = .init(.{ 0.8, 0.8, 0 }) } },
        ),
        Sphere.init(
            .init(.{ 0, 0, -1.2 }),
            0.5,
            .{ .lambertian = .{ .albedo = .init(.{ 0.1, 0.2, 0.5 }) } },
        ),
        Sphere.init(
            .init(.{ -1, 0, -1 }),
            0.5,
            .{ .metal = .{ .albedo = .init(.{ 0.8, 0.8, 0.8 }) } },
        ),
        Sphere.init(
            .init(.{ 1, 0, -1 }),
            0.5,
            .{ .metal = .{ .albedo = .init(.{ 0.8, 0.6, 0.2 }) } },
        ),
    };
    try camera.render(world);
}
