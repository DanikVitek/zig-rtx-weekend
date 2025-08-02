const std = @import("std");

const Vec3 = @import("Vec3.zig");
const Color = @import("Color.zig");

const objects = @import("objects.zig");
const Sphere = objects.Sphere;
const Material = objects.Material;
const camera = @import("camera.zig");
const rnd = @import("rnd.zig");

pub fn main() !void {
    const rand = rnd.random();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // skip program name
    const image_path = args.next() orelse "./img.ppm";
    if (!std.mem.endsWith(u8, image_path, ".ppm")) {
        std.debug.print("Supports only PPM image format", .{});
        return error.UnsupportedImageFormat;
    }

    var world: std.ArrayListUnmanaged(Sphere) = try .initCapacity(allocator, 22 * 22 + 4);
    defer world.deinit(allocator);

    const ground_material: Material = .{ .lambertian = .{ .albedo = .gray } };
    world.appendAssumeCapacity(.init(
        .init(.{ 0, -1000, 0 }),
        1000,
        ground_material,
    ));

    for (0..22) |a| {
        for (0..22) |b| {
            const choose_mat = rand.float(f64);
            const center: Vec3 = .init(.{
                @as(f64, @floatFromInt(a)) - 11.0 + 0.9 * rand.float(f64),
                0.2,
                @as(f64, @floatFromInt(b)) - 11.0 + 0.9 * rand.float(f64),
            });

            if (center.sub(.init(.{ 4, 0.2, 0 })).length() > 0.9) {
                const sphere_mat: Material = if (choose_mat < 0.8)
                    .{ .lambertian = .{ .albedo = .init(Vec3.random(rand).mul(.random(rand)).v) } }
                else if (choose_mat < 0.95)
                    .{ .metal = .{
                        .albedo = .init(Vec3.random(rand).add(.splat(1)).divScalar(2).v),
                        .fuzz = rand.float(f64) / 2,
                    } }
                else
                    .{ .dielectric = .{ .refraction_idx = 1.5 } };

                world.appendAssumeCapacity(.init(center, 0.2, sphere_mat));
            }
        }
    }

    const mat1: Material = .{ .dielectric = .{ .refraction_idx = 1.5 } };
    world.appendAssumeCapacity(.init(.init(.{ 0, 1, 0 }), 1, mat1));

    const mat2: Material = .{ .lambertian = .{ .albedo = .init(.{ 0.4, 0.2, 0.1 }) } };
    world.appendAssumeCapacity(.init(.init(.{ -4, 1, 0 }), 1, mat2));

    const mat3: Material = .{ .metal = .{ .albedo = .init(.{ 0.7, 0.6, 0.5 }) } };
    world.appendAssumeCapacity(.init(.init(.{ 4, 1, 0 }), 1, mat3));

    try camera.render(allocator, image_path, world.items);
}
