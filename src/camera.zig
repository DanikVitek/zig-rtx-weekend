const builtin = @import("builtin");

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Progress = std.Progress;
const Random = std.Random;

const Vec3 = @import("Vec3.zig");
const Vec2 = @import("Vec2.zig");
const Ray = @import("Ray.zig");
const Color = @import("Color.zig");

const objects = @import("objects.zig");
const Hit = objects.Hit;

/// Ratio of image width over height
pub const aspect_ratio = 16.0 / 9.0;
/// Rendered image width in pixel count
pub const img_width = 1920;

/// Count of random samples for each pixel
pub const samples_per_pixel = 100;
/// Maximum number of ray bounces into scene
pub const max_recursion = 50;

/// Vertical view angle (field of view)
pub const v_fov = 20.0; // 90.0;

/// Point camera is looking from
pub const look_from: Vec3 = .init(.{ 13, 2, 3 }); //.zero;
/// Point camera is looking at
pub const look_at: Vec3 = .zero;

/// Camera-relative "up" direction
pub const v_up: Vec3 = .y_axis;

/// Variation angle of rays through each pixel
pub const defocus_angle = 0.6; //0.0;
/// Distance from camera lookfrom point to plane of perfect focus
pub const focus_dist = 10.0; //10.0;

/// Rendered image height
const img_height = blk: {
    const fwidth: comptime_float = @floatFromInt(img_width);
    const h: comptime_int = @intFromFloat(fwidth / aspect_ratio);
    break :blk if (h < 1) 1 else h;
};

const camera_center: Vec3 = look_from;

const viewport_height = blk: {
    const theta: comptime_float = std.math.degreesToRadians(v_fov);
    const h: comptime_float = std.math.tan(theta / 2.0);
    break :blk 2 * h * focus_dist;
};
const viewport_width = blk: {
    const fwidth: comptime_float = @floatFromInt(img_width);
    const fheight: comptime_float = @floatFromInt(img_height);
    break :blk viewport_height * (fwidth + 0.0) / fheight;
};

/// Camera frame basis X axis
const u: Vec3 = v_up.cross(w).normalized();
/// Camera frame basis Y axis
const v: Vec3 = w.cross(u);
/// Camera frame basis Z axis
const w: Vec3 = look_from.sub(look_at).normalized();

const defocus_radius = focus_dist * std.math.tan(std.math.degreesToRadians(defocus_angle / 2.0));
/// Defocus disk horizontal radius
const defocus_disk_u: Vec3 = u.mulScalar(defocus_radius);
/// Defocus disk vertical radius
const defocus_disk_v: Vec3 = v.mulScalar(defocus_radius);

/// Vector across viewport horizontal edge
const viewport_u = u.mulScalar(viewport_width);
/// Vector down viewport vertical edge
const viewport_v = v.neg().mulScalar(viewport_height);

/// Offset to pixel to the right
const pixel_delta_u: Vec3 = viewport_u.divScalar(img_width);
/// Offset to pixel below
const pixel_delta_v: Vec3 = viewport_v.divScalar(img_height);

/// Location of pixel (0, 0)
const pixel00_loc: Vec3 = blk: {
    const viewport_upper_left: Vec3 = camera_center
        .sub(w.mulScalar(focus_dist))
        .sub(viewport_u.divScalar(2))
        .sub(viewport_v.divScalar(2));
    break :blk pixel_delta_u.add(pixel_delta_v).mulScalar(0.5).add(viewport_upper_left);
};

pub fn render(
    allocator: Allocator,
    rand: Random,
    image_path: []const u8,
    world: anytype,
) !void {
    const file = try std.fs.cwd().createFile(image_path, .{
        .read = true,
        .truncate = false,
        .exclusive = false,
    });
    defer file.close();

    const header_format = "P6\n{d} {d}\n255\n";
    var buf: [std.fmt.count(header_format, .{std.math.maxInt(u32)} ** 2)]u8 = undefined;
    const header: []const u8 = try std.fmt.bufPrint(&buf, header_format, .{ img_width, img_height });

    try file.setEndPos(header.len + img_width * img_height * 3);

    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        const metadata = try file.metadata();
        assert(metadata.size() == header.len + img_height * img_width * 3);
    }

    const ptr, const file_mapping = blk: {
        const result = try mmapImageFile(file, header.len + img_width * img_height * 3);
        break :blk if (@typeInfo(@TypeOf(result)) == .@"struct")
            result
        else
            .{ result, null };
    };
    defer if (builtin.os.tag != .windows) munmapImageFile(ptr);

    @memcpy(ptr[0..header.len], header);
    const image = std.mem.bytesAsSlice([3]u8, ptr[header.len..]);

    // const image = try allocator.alloc(Color, img_width * img_height);
    // defer allocator.free(image);
    // @memset(image, .{0} ** 3);

    const grid = try factorizeParallelizm();
    if (builtin.mode == .Debug) {
        std.debug.print("grid:\n  w: {d}\n  h: {d}\n", .{ grid.width, grid.height });
    }

    const progress = Progress.start(.{
        .estimated_total_items = grid.height * grid.width * grid.height * grid.width,
        .root_name = "rendering",
    });

    defer progress.end();
    var task_queue: TaskQueue(kernel) = undefined;
    try task_queue.init(allocator, grid.height * grid.height * grid.width * grid.width);
    errdefer task_queue.terminate(allocator);

    const whole_image_grid_cell_width = img_width / (grid.width * grid.width);
    const remainder_image_grid_cell_width = img_width % (grid.width * grid.width);
    const whole_image_grid_cell_height = img_height / (grid.height * grid.height);
    const remainder_image_grid_cell_height = img_height % (grid.height * grid.height);
    for (0..grid.height * grid.height) |i| {
        for (0..grid.width * grid.width) |j| {
            const kernel_x = j * (whole_image_grid_cell_width + @intFromBool(j < remainder_image_grid_cell_width + 1));
            const kernel_y = i * (whole_image_grid_cell_height + @intFromBool(i < remainder_image_grid_cell_height + 1));

            const kernel_width = whole_image_grid_cell_width + @intFromBool(j < remainder_image_grid_cell_width);
            const kernel_height = whole_image_grid_cell_height + @intFromBool(i < remainder_image_grid_cell_height);

            try task_queue.addTask(allocator, .{
                .args = .{
                    kernel_x,
                    kernel_y,
                    kernel_width,
                    kernel_height,
                    world,
                    image,
                    progress,
                    rand,
                },
            });
        }
    }

    task_queue.runToCompletion(allocator);

    if (builtin.os.tag == .windows) try munmapImageFile(ptr, file_mapping);
}

fn factorizeParallelizm() !struct { width: Sqrt(usize), height: Sqrt(usize) } {
    const parallelizm: usize = try Thread.getCpuCount();

    const width: Sqrt(usize) = std.math.sqrt(parallelizm);
    const height: Sqrt(usize) = @intCast(try std.math.divExact(usize, parallelizm, width));

    return .{ .width = @max(width, height), .height = @min(width, height) };
}

fn Sqrt(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int => |info| std.meta.Int(.unsigned, (info.bits + 1) / 2),
        else => T,
    };
}

fn kernel(
    kx: usize,
    ky: usize,
    kw: usize,
    kh: usize,
    world: []const objects.Sphere,
    image: [][3]u8,
    progress: std.Progress.Node,
    rand: Random,
) void {
    const fmt = "T: {d}; x: {d}, y: {d}, w: {d}, h: {d}";
    var name_buf: [std.fmt.count(fmt, .{std.math.maxInt(Thread.Id)} ++ .{std.math.maxInt(usize)} ** 4)]u8 = undefined;
    const name: []const u8 = std.fmt.bufPrint(&name_buf, fmt, .{ Thread.getCurrentId(), kx, ky, kw, kh }) catch unreachable;

    const kprogress = progress.start(name, kw * kh * samples_per_pixel);
    defer kprogress.end();

    for (kx..kx + kw) |x| {
        for (ky..ky + kh) |y| {
            var pixel: Color = .black;
            for (0..samples_per_pixel) |_| {
                const ray: Ray = getRay(
                    rand,
                    @floatFromInt(x),
                    @floatFromInt(y),
                );
                pixel.v += rayColor(ray, rand, world, 0).v;

                kprogress.completeOne();
            }
            pixel.v /= @splat(samples_per_pixel);
            var pixel_bytes: [3]u8 = undefined;
            _ = std.fmt.bufPrint(&pixel_bytes, "{}", .{pixel}) catch unreachable;
            image[y * img_width + x] = pixel_bytes;
        }
    }
}

fn getRay(rand: Random, x: f64, y: f64) Ray {
    const offset = sampleSquare(rand);
    const pixel_sample: Vec3 = .mulScalarAdd(
        y + offset.y(),
        pixel_delta_v,
        .mulScalarAdd(
            x + offset.x(),
            pixel_delta_u,
            pixel00_loc,
        ),
    );

    const ray_origin = if (defocus_angle <= 0) camera_center else defocusDiskScample(rand);
    const ray_dir: Vec3 = pixel_sample.sub(ray_origin);

    return .init(ray_origin, ray_dir);
}

fn sampleSquare(rand: Random) Vec2 {
    return .init(.{
        rand.float(f64) - 0.5,
        rand.float(f64) - 0.5,
    });
}

fn defocusDiskScample(rand: Random) Vec3 {
    const p: Vec2 = .randomInUnitDisk(rand);
    return .mulScalarAdd(
        p.x(),
        defocus_disk_u,
        .mulScalarAdd(
            p.y(),
            defocus_disk_v,
            camera_center,
        ),
    );
}

fn rayColor(
    ray: Ray,
    rand: Random,
    world: anytype,
    depth: std.math.IntFittingRange(0, max_recursion + 1),
) Color {
    if (depth > max_recursion) return .black;

    if (hitWorld(world, ray)) |hit| {
        return if (hit.material.scatter(rand, ray, hit)) |scatter|
            scatter.attenuation.mul(rayColor(scatter.scattered_ray, rand, world, depth + 1))
        else
            .black;
    }

    const unit_direction = ray.dir.normalized();
    const a: f64 = 0.5 * (unit_direction.y() + 1.0);
    const wat: Color = .init(.{ 0.5, 0.7, 1 });
    return .mulScalarAdd(a, wat, .splat(1.0 - a));
}

fn hitWorld(objs: anytype, ray: Ray) ?Hit {
    var hit: ?Hit = null;
    var closest_so_far = std.math.inf(f64);
    for (objs) |obj| {
        if (obj.hit(ray, .{ .min = 0.001, .max = closest_so_far })) |h| {
            hit = h;
            closest_so_far = hit.?.t;
        }
    }
    return hit;
}

fn TaskQueue(comptime func: anytype) type {
    return struct {
        mutex: Mutex = .{},
        tasks: Tasks = .empty,
        run_to_exhaustion: AtomicBool = .init(false),
        kill: AtomicBool = .init(false),
        threads: []Thread,

        const Self = @This();
        const Mutex = std.Thread.Mutex;
        const AtomicBool = std.atomic.Value(bool);
        const Tasks = std.ArrayListUnmanaged(Task(func));

        pub fn init(self: *Self, allocator: Allocator, tasks_cap: ?usize) !void {
            const parallelism = try Thread.getCpuCount();
            const threads = try allocator.alloc(Thread, parallelism);

            self.* = .{ .threads = threads };
            if (tasks_cap) |cap| {
                self.tasks = try Tasks.initCapacity(allocator, cap);
            }

            std.debug.print("Parallelism: {d}\n", .{parallelism});
            for (0..parallelism) |i| {
                threads[i] = try Thread.spawn(
                    .{ .allocator = allocator },
                    struct {
                        fn f(
                            tasks: *Tasks,
                            mutex: *Mutex,
                            kill: *const AtomicBool,
                            run_to_exhaustion: *const AtomicBool,
                        ) Task(func).Return {
                            while (!kill.load(.acquire)) {
                                if (mutex.tryLock()) {
                                    const maybe_task = blk: {
                                        defer mutex.unlock();
                                        break :blk tasks.pop();
                                    };
                                    if (maybe_task) |task| {
                                        if (@typeInfo(Task(func).Return) == .error_union) {
                                            if (Task(func).Return == !void) {
                                                try task.run();
                                            } else {
                                                @compileError("expected func to return `void` or `!void`");
                                            }
                                        } else if (Task(func).Return == void) {
                                            task.run();
                                        } else {
                                            @compileError("expected func to return `void` or `!void`");
                                        }
                                    } else if (run_to_exhaustion.load(.acquire)) break;
                                }
                            }
                        }
                    }.f,
                    .{
                        &self.tasks,
                        &self.mutex,
                        &self.kill,
                        &self.run_to_exhaustion,
                    },
                );
            }
        }

        pub fn addTask(self: *Self, allocator: Allocator, task: Task(func)) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.tasks.append(allocator, task);
        }

        pub fn addTaskAssumeCapacity(self: *Self, task: Task(func)) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.tasks.appendAssumeCapacity(task);
        }

        pub fn runToCompletion(self: *Self, allocator: Allocator) void {
            defer allocator.free(self.threads);
            self.run_to_exhaustion.store(true, .release);
            for (self.threads) |thread| {
                thread.join();
            }
        }

        pub fn terminate(self: *Self, allocator: Allocator) void {
            defer allocator.free(self.threads);
            self.kill.store(true, .release);
            for (self.threads) |thread| {
                thread.join();
            }
        }
    };
}

fn Task(comptime func: anytype) type {
    const Fn = @TypeOf(func);
    return struct {
        args: Args,

        pub const Args = std.meta.ArgsTuple(@TypeOf(func));
        pub const Return = switch (@typeInfo(Fn)) {
            .@"fn" => |info| info.return_type.?,
            else => @compileError("Expected `func` to be a function"),
        };

        fn run(self: @This()) Return {
            return @call(.auto, func, self.args);
        }
    };
}

fn mmapImageFile(file: std.fs.File, size: usize) !switch (builtin.os.tag) {
    .wasi => @compileError("unsupported"),
    .windows => struct { []u8, @import("windows.zig").HANDLE },
    else => []align(std.heap.page_size_min) u8,
} {
    return switch (builtin.os.tag) {
        .windows => blk: {
            const windows = @import("windows.zig");
            const DWORD = windows.DWORD;
            const CreateFileMapping = windows.CreateFileMappingA;
            const MapViewOfFile = windows.MapViewOfFile;
            const CloseHandle = windows.CloseHandle;

            const file_mapping: windows.HANDLE = CreateFileMapping(
                file.handle,
                null,
                .PAGE_READWRITE,
                @as(DWORD, @intCast(size >> 32)),
                @as(DWORD, @intCast(size & std.math.maxInt(DWORD))),
                null,
            ) orelse {
                const err = std.os.windows.GetLastError();
                std.log.err("Failed to create file mapping ({d})", .{@intFromEnum(err)});
                break :blk error.FileMappingFailed;
            };
            errdefer CloseHandle(file_mapping);

            const ptr = MapViewOfFile(
                file_mapping,
                windows.FILE_MAP_ALL_ACCESS,
                0,
                0,
                size,
            ) orelse {
                const err = std.os.windows.GetLastError();
                std.log.err("Failed to map view of file ({d})", .{@intFromEnum(err)});
                break :blk error.FileMappingFailed;
            };

            const many_ptr: [*]u8 = @ptrCast(ptr);
            return .{ many_ptr[0..size], file_mapping };
        },
        else => try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        ),
    };
}

const munmapImageFile = switch (builtin.os.tag) {
    .wasi => @compileError("unsupported"),
    .windows => struct {
        fn f(ptr: []const u8, file_mapping: std.os.windows.HANDLE) !void {
            const windows = @import("windows.zig");
            const UnmapViewOfFile = windows.UnmapViewOfFile;
            const FlushViewOfFile = windows.FlushViewOfFile;
            const CloseHandle = windows.CloseHandle;

            if (UnmapViewOfFile(ptr.ptr) == 0) {
                const err = std.os.windows.GetLastError();
                std.log.err("Failed to unmap view of file ({d})", .{@intFromEnum(err)});
                return error.UnmapViewOfFileFailed;
            }

            if (FlushViewOfFile(ptr.ptr, 0) == 0) {
                const err = std.os.windows.GetLastError();
                std.log.err("Failed to flush view of file ({d})", .{@intFromEnum(err)});
                return error.FlushViewOfFileFailed;
            }
            CloseHandle(file_mapping);
        }
    }.f,
    else => std.posix.munmap,
};
