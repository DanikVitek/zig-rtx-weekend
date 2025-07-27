const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;

const Vec3 = @import("Vec3.zig");
const Color = @import("Color.zig");
const Ray = @import("Ray.zig");
const Interval = @import("Interval.zig");

pub const Hit = struct {
    p: Vec3,
    norm: Vec3,
    t: f64,
    front_face: bool,
    material: Material,

    pub fn init(
        t: f64,
        ray: Ray,
        p: Vec3,
        outward_normal: Vec3,
        material: Material,
    ) Hit {
        if (builtin.mode == .Debug) {
            // NOTE: the parameter `outward_normal` is assumed to have unit length.
            const one = outward_normal.magnitude2();
            assert(std.math.approxEqAbs(f64, one, 1, 1e-5));
        }

        const front_face = ray.dir.dot(outward_normal) < 0;
        const norm = if (front_face) outward_normal else outward_normal.neg();
        return .{
            .p = p,
            .t = t,
            .front_face = front_face,
            .norm = norm,
            .material = material,
        };
    }
};

pub const Material = union(enum) {
    lambertian: struct {
        albedo: Color,
    },
    metal: struct {
        albedo: Color,
        diffusion: Vec3 = .zero,
    },

    pub const Scatter = struct {
        attenuation: Color,
        scattered: Ray,
    };

    pub fn scatter(self: Material, rand: std.Random, ray_in: Ray, hit: Hit) ?Scatter {
        return switch (self) {
            .lambertian => |m| blk: {
                var dir: Vec3 = hit.norm.add(.randomUnit(rand));

                if (dir.isNearZero()) dir = hit.norm;

                break :blk .{
                    .scattered = .init(hit.p, dir),
                    .attenuation = m.albedo,
                };
            },
            .metal => |m| blk: {
                const reflected: Vec3 = ray_in.dir.reflect(hit.norm);
                break :blk .{
                    .scattered = .init(hit.p, reflected),
                    .attenuation = m.albedo,
                };
            },
        };
    }
};

pub const Sphere = struct {
    center: Vec3,
    radius: f64,
    material: Material,

    pub fn init(center: Vec3, radius: f64, material: Material) Sphere {
        assert(radius >= 0);
        return .{
            .center = center,
            .radius = radius,
            .material = material,
        };
    }

    pub fn hit(self: Sphere, ray: Ray, ray_t: Interval) ?Hit {
        const center: Vec3 = self.center;
        const radius: f64 = self.radius;

        const oc: Vec3 = .init(self.center.v - ray.orig.v);
        const a: f64 = ray.dir.magnitude2();
        const h: f64 = ray.dir.dot(oc);
        const c: f64 = oc.magnitude2() - radius * radius;
        const discriminant: f64 = h * h - a * c;

        if (discriminant < 0) return null;

        const sqrtd: f64 = @sqrt(discriminant);

        // find the nearest root that lies in the acceptable range
        var root: f64 = (h - sqrtd) / a;
        if (!ray_t.surrounds(root)) {
            root = (h + sqrtd) / a;
            if (!ray_t.surrounds(root))
                return null;
        }

        const p: Vec3 = ray.at(root);
        const outward_normal: Vec3 = p.sub(center).divScalar(radius);
        return .init(root, ray, p, outward_normal, self.material);
    }
};
