const std = @import("std");
const vec = @import("vec.zig");
const Vec3 = vec.Vec3;

orig: Vec3,
dir: Vec3,

const Ray = @This();

pub fn init(orig: Vec3, dir: Vec3) Ray {
    return Ray{ .orig = orig, .dir = dir };
}

pub fn at(r: Ray, t: f64) Vec3 {
    const tvec: Vec3 = @splat(t);
    return r.orig + tvec * r.dir;
}
