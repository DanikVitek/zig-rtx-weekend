const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;

const Vec3 = @import("Vec3.zig");
const Ray = @import("Ray.zig");
const Interval = @import("Interval.zig");

pub const Hit = struct {
    p: Vec3,
    norm: Vec3,
    t: f64,
    front_face: bool,

    pub fn init(
        t: f64,
        ray: Ray,
        p: Vec3,
        outward_normal: Vec3,
    ) Hit {
        if (builtin.mode == .Debug) {
            // NOTE: the parameter `outward_normal` is assumed to have unit length.
            const one = outward_normal.magnitude2();
            assert(std.math.approxEqAbs(f64, one, 1, 0.0001));
        }

        const front_face = ray.dir.dot(outward_normal) < 0;
        const norm = if (front_face) outward_normal else outward_normal.neg();
        return .{
            .p = p,
            .t = t,
            .front_face = front_face,
            .norm = norm,
        };
    }
};

pub const Sphere = struct {
    center: Vec3,
    radius: f64,

    pub fn init(center: Vec3, radius: f64) Sphere {
        return .{
            .center = center,
            .radius = radius,
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
        return .init(root, ray, p, outward_normal);
    }
};
