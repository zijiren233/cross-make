/*
 * Alias launcher for the windows-hosted clang distribution.
 *
 * Windows has no symlinks, so every bin/<triple>-<tool>.exe is a copy of
 * this small program instead of a copy of the 100MB+ LLVM executable. The
 * alias name supplies both the target triple and the tool: compiler driver
 * modes get --target=<triple> prepended, which makes the real driver load
 * the implicit <normalized-triple>-<mode>.cfg next to itself in clang/bin
 * and resolve its resource dir, runtimes and lld from there. The tail of
 * the raw command line is forwarded verbatim, so argument quoting is never
 * reinterpreted.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

struct alias {
	const wchar_t *tool;
	const wchar_t *exe;
	int target;
};

static const struct alias aliases[] = {
	{L"clang", L"clang.exe", 1},
	{L"clang++", L"clang++.exe", 1},
	{L"gcc", L"clang.exe", 1},
	{L"g++", L"clang++.exe", 1},
	{L"cc", L"clang.exe", 1},
	{L"c++", L"clang++.exe", 1},
	{L"clang-cpp", L"clang-cpp.exe", 1},
	{L"cpp", L"clang-cpp.exe", 1},
	{L"ld", L"ld.lld.exe", 0},
	{L"windres", L"llvm-windres.exe", 0},
	{NULL, NULL, 0},
};

static int fail(const wchar_t *msg, const wchar_t *detail)
{
	fwprintf(stderr, L"launcher: %ls%ls%ls\n", msg, detail ? L": " : L"", detail ? detail : L"");
	return 1;
}

/* Skip our own argv[0] in the raw command line (quoted or bare). */
static const wchar_t *command_tail(void)
{
	const wchar_t *p = GetCommandLineW();
	if (*p == L'"') {
		p++;
		while (*p && *p != L'"')
			p++;
		if (*p)
			p++;
	} else {
		while (*p && *p != L' ' && *p != L'\t')
			p++;
	}
	while (*p == L' ' || *p == L'\t')
		p++;
	return p;
}

int wmain(int argc, wchar_t **argv)
{
	(void)argc;
	(void)argv;
	wchar_t self[32768];
	DWORD n = GetModuleFileNameW(NULL, self, sizeof(self) / sizeof(self[0]));
	if (n == 0 || n >= sizeof(self) / sizeof(self[0]))
		return fail(L"cannot resolve own path", NULL);

	wchar_t *base = wcsrchr(self, L'\\');
	base = base ? base + 1 : self;
	size_t dirlen = (size_t)(base - self);

	wchar_t *dot = wcsrchr(base, L'.');
	if (dot && _wcsicmp(dot, L".exe") == 0)
		*dot = 0;

	wchar_t *dash = wcsrchr(base, L'-');
	if (!dash || dash == base)
		return fail(L"alias name carries no <triple>- prefix", base);
	*dash = 0;
	const wchar_t *triple = base;
	const wchar_t *tool = dash + 1;

	const wchar_t *exe = NULL;
	int target = 0;
	for (const struct alias *a = aliases; a->tool; a++) {
		if (_wcsicmp(a->tool, tool) == 0) {
			exe = a->exe;
			target = a->target;
			break;
		}
	}
	wchar_t llvm_tool[128];
	if (!exe) {
		/* ar, nm, objcopy, strip, readobj, rc, ... -> llvm-<tool>.exe */
		swprintf(llvm_tool, sizeof(llvm_tool) / sizeof(llvm_tool[0]), L"llvm-%ls.exe", tool);
		exe = llvm_tool;
	}

	/* the real tools live in ../clang/bin relative to this bin/ */
	size_t reallen = dirlen + wcslen(L"..\\clang\\bin\\") + wcslen(exe) + 1;
	wchar_t *real = malloc(reallen * sizeof(wchar_t));
	if (!real)
		return fail(L"out of memory", NULL);
	wcsncpy(real, self, dirlen);
	real[dirlen] = 0;
	wcscat(real, L"..\\clang\\bin\\");
	wcscat(real, exe);

	const wchar_t *tail = command_tail();
	size_t cmdlen = wcslen(real) + wcslen(triple) + wcslen(tail) + 32;
	wchar_t *cmd = malloc(cmdlen * sizeof(wchar_t));
	if (!cmd)
		return fail(L"out of memory", NULL);
	if (target)
		swprintf(cmd, cmdlen, L"\"%ls\" --target=%ls%ls%ls", real, triple, *tail ? L" " : L"", tail);
	else
		swprintf(cmd, cmdlen, L"\"%ls\"%ls%ls", real, *tail ? L" " : L"", tail);

	STARTUPINFOW si;
	PROCESS_INFORMATION pi;
	memset(&si, 0, sizeof(si));
	si.cb = sizeof(si);
	if (!CreateProcessW(real, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
		wchar_t err[64];
		swprintf(err, sizeof(err) / sizeof(err[0]), L"(error %lu)", (unsigned long)GetLastError());
		fwprintf(stderr, L"launcher: cannot start %ls %ls\n", real, err);
		return 1;
	}
	CloseHandle(pi.hThread);
	WaitForSingleObject(pi.hProcess, INFINITE);
	DWORD code = 1;
	GetExitCodeProcess(pi.hProcess, &code);
	CloseHandle(pi.hProcess);
	return (int)code;
}
