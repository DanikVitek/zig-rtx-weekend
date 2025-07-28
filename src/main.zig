const std = @import("std");

const Vec3 = @import("Vec3.zig");
const Color = @import("Color.zig");

const objects = @import("objects.zig");
const Sphere = objects.Sphere;
const camera = @import("camera.zig");

pub fn main() !void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // var gpa: std.heap.ThreadSafeAllocator = .{ .child_allocator = arena.allocator() };
    // const allocaror = gpa.allocator();
    // const allocaror = arena.allocator();

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa.deinit() != .ok) @panic("leak");
    const allocator = gpa.allocator();
    var rand_state = std.Random.DefaultPrng.init(42);
    const rand = rand_state.random();

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
    try camera.render(world, allocator, rand);
}
