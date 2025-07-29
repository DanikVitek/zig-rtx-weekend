const std = @import("std");
const windows = std.os.windows;
pub const HANDLE = windows.HANDLE;
pub const DWORD = windows.DWORD;
pub const BOOL = windows.BOOL;
pub const BYTE = windows.BYTE;
pub const LPVOID = windows.LPVOID;
pub const LPCVOID = windows.LPCVOID;
pub const LPCSTR = windows.LPCSTR;
pub const SIZE_T = windows.SIZE_T;

const SECURITY_ATTRIBUTES = extern struct {
    nLength: DWORD,
    lpSecurityDescriptor: ?*anyopaque = null,
    bInheritHandle: BOOL,
};

pub extern "kernel32" fn CreateFileMappingA(
    hFile: HANDLE,
    lpFileMappingAttributes: ?*SECURITY_ATTRIBUTES,
    flProtect: FlProtect,
    dwMaximumSizeHigh: DWORD,
    dwMaximumSizeLow: DWORD,
    lpName: ?LPCSTR,
) ?HANDLE;

pub extern "kernel32" fn MapViewOfFile(
    hFileMappingObject: HANDLE,
    dwDesiredAccess: DWORD,
    dwFileOffsetHigh: DWORD,
    dwFileOffsetLow: DWORD,
    dwNumberOfBytesToMap: SIZE_T,
) ?LPVOID;

pub const CloseHandle = windows.CloseHandle;

pub extern "kernel32" fn FlushViewOfFile(
    lpBaseAddress: LPCVOID,
    dwNumberOfBytesToFlush: SIZE_T,
) BOOL;

pub extern "kernel32" fn UnmapViewOfFile(lpBaseAddress: LPCVOID) BOOL;

pub const FlProtect = enum(DWORD) {
    PAGE_READONLY = 0x02,
    PAGE_READWRITE = 0x04,
    PAGE_WRITECOPY = 0x08,
    PAGE_EXECUTE_READ = 0x20,
    PAGE_EXECUTE_READWRITE = 0x40,
    PAGE_EXECUTE_WRITECOPY = 0x80,
};

pub const FILE_MAP_ALL_ACCESS = windows.SECTION_ALL_ACCESS;
pub const FILE_MAP_READ = windows.SECTION_MAP_READ;
pub const FILE_MAP_WRITE = windows.SECTION_MAP_WRITE;

pub const FILE_MAP_COPY = 0x00000001;
pub const FILE_MAP_EXECUTE = 0x20; // windows.SECTION_MAP_EXECUTE_EXPLICIT
pub const FILE_MAP_LARGE_PAGES = 0x20000000;
pub const FILE_MAP_TARGETS_INVALID = 0x40000000;

// pub const DesiredAccess = packed struct(DWORD) {
//     FILE_MAP_READ: bool = false,
//     FILE_MAP_WRITE: bool = false,
//     FILE_MAP_COPY: bool = false,

//     const FILE_MAP_ALL_ACCESS: DesiredAccess = .{ .FILE_MAP_READ = true, .FILE_MAP_WRITE = true };
// };
