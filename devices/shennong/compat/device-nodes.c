/* SPDX-License-Identifier: GPL-2.0-only */
/* Stock Android kernels lack devtmpfs. Create nodes without handling firmware
 * requests or competing with udev for its netlink event stream. */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

static gid_t group_id(const char *wanted) {
    char line[1024], name[256];
    unsigned id;
    FILE *file = fopen("/etc/group", "re");
    if (!file) return 0;
    while (fgets(line, sizeof(line), file)) {
        if (sscanf(line, "%255[^:]:%*[^:]:%u:", name, &id) == 2 &&
            !strcmp(name, wanted)) {
            fclose(file);
            return (gid_t)id;
        }
    }
    fclose(file);
    return 0;
}

static int create_node(const char *name, unsigned major_id, unsigned minor_id,
                       int block) {
    char path[PATH_MAX];
    struct stat st;
    mode_t mode = (block ? S_IFBLK : S_IFCHR) | 0600;
    gid_t gid = 0;
    if (!name || !*name || *name == '/' || strstr(name, "..") ||
        snprintf(path, sizeof(path), "/dev/%s", name) >= (int)sizeof(path))
        return -1;
    dev_t device = makedev(major_id, minor_id);
    if (lstat(path, &st) == 0) {
        /* Preserve permissions already assigned by udev, and never replace
         * existing files or symlinks such as /dev/ptmx. */
        return ((S_ISCHR(st.st_mode) || S_ISBLK(st.st_mode)) &&
                st.st_rdev == device) || S_ISLNK(st.st_mode) ? 0 : -1;
    }
    if (!block && (!strcmp(name, "null") || !strcmp(name, "zero") ||
                   !strcmp(name, "full") || !strcmp(name, "random") ||
                   !strcmp(name, "urandom") || !strcmp(name, "tty") ||
                   !strcmp(name, "ptmx")))
        mode = S_IFCHR | 0666;
    if (!strncmp(name, "input/", 6)) gid = group_id("input");
    else if (!strncmp(name, "dri/render", 10)) gid = group_id("render");
    else if (!strncmp(name, "dri/", 4)) gid = group_id("video");
    if (gid) mode = (mode & S_IFMT) | 0660;
    for (char *p = path + 5; *p; ++p) {
        if (*p != '/') continue;
        *p = 0;
        if (mkdir(path, 0755) != 0 && errno != EEXIST) return -1;
        *p = '/';
    }
    if (mknod(path, mode, device) != 0) return errno == EEXIST ? 0 : -1;
    if (chown(path, 0, gid) || chmod(path, mode & 0777)) return -1;
    return 0;
}

static int scan(const char *directory, int block) {
    DIR *dir = opendir(directory);
    if (!dir) return -1;
    struct dirent *entry;
    int failures = 0;
    while ((entry = readdir(dir))) {
        unsigned major_id, minor_id;
        char filename[PATH_MAX], line[PATH_MAX], name[PATH_MAX] = "";
        if (sscanf(entry->d_name, "%u:%u", &major_id, &minor_id) != 2) continue;
        snprintf(filename, sizeof(filename), "%s/%s/uevent", directory, entry->d_name);
        FILE *file = fopen(filename, "re");
        if (!file) continue; /* An unplugged device can disappear during scan. */
        while (fgets(line, sizeof(line), file)) {
            if (strncmp(line, "DEVNAME=", 8)) continue;
            line[strcspn(line, "\r\n")] = 0;
            snprintf(name, sizeof(name), "%s", line + 8);
        }
        fclose(file);
        if (*name && create_node(name, major_id, minor_id, block)) {
            fprintf(stderr, "cannot create /dev/%s: %s\n", name, strerror(errno));
            ++failures;
        }
    }
    closedir(dir);
    return failures ? -1 : 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--scan")) {
        int a = scan("/sys/dev/char", 0);
        int b = scan("/sys/dev/block", 1);
        return a || b ? 1 : 0;
    }
    if (argc == 2 && !strcmp(argv[1], "--event")) {
        const char *name = getenv("DEVNAME"), *maj = getenv("MAJOR");
        const char *min = getenv("MINOR"), *sub = getenv("SUBSYSTEM");
        char *end;
        if (!name || !maj || !min || !sub) return 1;
        unsigned long major_id = strtoul(maj, &end, 10);
        if (!*maj || *end || major_id > UINT_MAX) return 1;
        unsigned long minor_id = strtoul(min, &end, 10);
        if (!*min || *end || minor_id > UINT_MAX) return 1;
        if (!strncmp(name, "/dev/", 5)) name += 5;
        return create_node(name, major_id, minor_id, !strcmp(sub, "block")) ? 1 : 0;
    }
    fprintf(stderr, "usage: %s --scan|--event\n", argv[0]);
    return 2;
}
