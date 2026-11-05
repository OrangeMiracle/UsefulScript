import ctypes
from ctypes import wintypes as W
from pathlib import Path
import subprocess
import time
import json

def event(folder, name, **data):
    with (Path(folder) / "handles.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps({"event": name, **data}, ensure_ascii=False) + "\n")

def owners(path):
    """Windows Restart Manager: all processes holding DB/WAL/SHM files."""
    class Unique(ctypes.Structure):
        _fields_ = [('pid', W.DWORD), ('start', W.FILETIME)]
    class Info(ctypes.Structure):
        _fields_ = [('process', Unique), ('name', W.WCHAR * 256), ('service', W.WCHAR * 64),
                    ('app_type', ctypes.c_int), ('status', W.ULONG), ('session', W.DWORD), ('restartable', W.BOOL)]
    dll = ctypes.WinDLL('rstrtmgr')
    h = W.DWORD()
    key = ctypes.create_unicode_buffer(33)
    err = dll.RmStartSession(ctypes.byref(h), 0, key)
    if err:
        raise ctypes.WinError(err)
    try:
        paths = [str(p) for p in [path, Path(str(path) + '-wal'), Path(str(path) + '-shm')] if p.exists()]
        resources = (W.LPCWSTR * len(paths))(*paths)
        err = dll.RmRegisterResources(h, len(paths), resources, 0, None, 0, None)
        if err:
            raise ctypes.WinError(err)
        needed, count, reason = W.UINT(), W.UINT(), W.DWORD()
        err = dll.RmGetList(h, ctypes.byref(needed), ctypes.byref(count), None, ctypes.byref(reason))
        if err == 0:
            return []
        if err != 234:
            raise ctypes.WinError(err)
        for _ in range(3):
            count.value = needed.value
            buffer = (Info * count.value)()
            err = dll.RmGetList(h, ctypes.byref(needed), ctypes.byref(count), buffer, ctypes.byref(reason))
            if not err:
                return [{'pid': x.process.pid, 'name': x.name} for x in buffer[:count.value]]
            if err != 234:
                raise ctypes.WinError(err)
        raise RuntimeError('Owner list changed repeatedly')
    finally:
        dll.RmEndSession(h)

def require_quiet(path, folder):
    listing = subprocess.run(['tasklist.exe', '/FI', 'IMAGENAME eq ChatGPT.exe', '/FO', 'CSV', '/NH'], capture_output=True, check=True)
    if b'chatgpt.exe' in listing.stdout.lower():
        raise RuntimeError('ChatGPT desktop is running; no database changes allowed')
    for _ in range(3):
        result = owners(path)
        event(folder, 'database_owners', owners=result)
        if result:
            raise RuntimeError('Database is still in use; no changes made')
        handles = []
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.CreateFileW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, W.LPVOID, W.DWORD, W.DWORD, W.HANDLE]
        kernel.CreateFileW.restype = W.HANDLE
        kernel.CloseHandle.argtypes = [W.HANDLE]
        try:
            for p in [path, Path(str(path) + '-wal'), Path(str(path) + '-shm')]:
                if not p.exists():
                    continue
                h = kernel.CreateFileW(str(p), 0x80000000, 0, None, 3, 0x80, None)
                if h == ctypes.c_void_p(-1).value:
                    raise ctypes.WinError(ctypes.get_last_error())
                handles.append(h)
        finally:
            for h in handles:
                kernel.CloseHandle(h)
        time.sleep(0.5)
    event(folder, 'exclusive_file_open_checks', passed=True)
