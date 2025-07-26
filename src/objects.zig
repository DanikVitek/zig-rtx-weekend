const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;

const vec = @import("vec.zig");
const Vec3 = vec.Vec3;
const Ray = @import("Ray.zig");

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
            const one = vec.magnitudeSquared(outward_normal);
            assert(std.math.approxEqAbs(f64, one, 1, 0.0001));
        }

        const front_face = vec.dot(ray.dir, outward_normal) < 0;
        const norm = if (front_face) outward_normal else -outward_normal;
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

    pub fn hit(self: *const Sphere, ray: Ray, ray_tmin: f64, ray_tmax: f64) ?Hit {
        const center = self.center;
        const radius = self.radius;

        const oc = self.center - ray.orig;
        const a = vec.magnitudeSquared(ray.dir);
        const h = vec.dot(ray.dir, oc);
        const c = vec.magnitudeSquared(oc) - radius * radius;
        const discriminant = h * h - a * c;

        if (discriminant < 0) return null;

        const sqrtd = @sqrt(discriminant);

        // find the nearest root that lies in the acceptable range
        var root = (h - sqrtd) / a;
        if (root <= ray_tmin or ray_tmax <= root) {
            root = (h + sqrtd) / a;
            if (root <= ray_tmin or ray_tmax <= root)
                return null;
        }

        const t = root;
        const p = ray.at(t);
        const outward_normal = (p - center) / vec.splat(radius);
        return .init(t, ray, p, outward_normal);
    }
};
