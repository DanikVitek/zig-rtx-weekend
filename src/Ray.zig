const std = @import("std");
const Vec3 = @import("Vec3.zig");

orig: Vec3,
dir: Vec3,

const Ray = @This();

pub fn init(orig: Vec3, dir: Vec3) Ray {
    return Ray{ .orig = orig, .dir = dir };
}

pub fn at(r: Ray, t: f64) Vec3 {
    return r.dir.mulScalarAdd(t, r.orig);
}
