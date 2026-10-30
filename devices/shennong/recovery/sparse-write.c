#define _FILE_OFFSET_BITS 64

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/fs.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define SPARSE_MAGIC 0xed26ff3aU
#define CHUNK_RAW 0xcac1U
#define CHUNK_FILL 0xcac2U
#define CHUNK_DONT_CARE 0xcac3U
#define CHUNK_CRC32 0xcac4U
#define EXPECTED_TARGET_BYTES UINT64_C(214748364800)
#define EXPECTED_IMAGE_BYTES UINT64_C(8589934592)

struct __attribute__((packed)) sparse_header {
    uint32_t magic;
    uint16_t major_version;
    uint16_t minor_version;
    uint16_t file_hdr_sz;
    uint16_t chunk_hdr_sz;
    uint32_t blk_sz;
    uint32_t total_blks;
    uint32_t total_chunks;
    uint32_t image_checksum;
};

struct __attribute__((packed)) chunk_header {
    uint16_t chunk_type;
    uint16_t reserved;
    uint32_t chunk_sz;
    uint32_t total_sz;
};

static void die(const char *format, ...) {
    va_list args;
    va_start(args, format);
    fputs("sparse-write: ", stderr);
    vfprintf(stderr, format, args);
    fputc('\n', stderr);
    va_end(args);
    exit(1);
}

static void read_exact(int fd, void *buffer, size_t size) {
    unsigned char *cursor = buffer;
    while (size > 0) {
        ssize_t count = read(fd, cursor, size);
        if (count == 0) {
            die("unexpected end of sparse input");
        }
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            die("read failed: %s", strerror(errno));
        }
        cursor += (size_t)count;
        size -= (size_t)count;
    }
}

static void discard_exact(int fd, uint64_t size) {
    unsigned char buffer[4096];
    while (size > 0) {
        size_t part = size < sizeof(buffer) ? (size_t)size : sizeof(buffer);
        read_exact(fd, buffer, part);
        size -= part;
    }
}

static void write_exact(int fd, const void *buffer, size_t size) {
    const unsigned char *cursor = buffer;
    while (size > 0) {
        ssize_t count = write(fd, cursor, size);
        if (count == 0) {
            die("write returned zero bytes");
        }
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            die("write failed: %s", strerror(errno));
        }
        cursor += (size_t)count;
        size -= (size_t)count;
    }
}

static void copy_exact(int input, int output, uint64_t size) {
    unsigned char *buffer = malloc(1024 * 1024);
    if (buffer == NULL) {
        die("cannot allocate copy buffer");
    }
    while (size > 0) {
        size_t part = size < 1024 * 1024 ? (size_t)size : 1024 * 1024;
        read_exact(input, buffer, part);
        write_exact(output, buffer, part);
        size -= part;
    }
    free(buffer);
}

static void write_fill(int output, uint32_t pattern, uint64_t size) {
    uint32_t *buffer = malloc(1024 * 1024);
    if (buffer == NULL) {
        die("cannot allocate fill buffer");
    }
    for (size_t index = 0; index < (1024 * 1024) / sizeof(pattern); ++index) {
        buffer[index] = pattern;
    }
    while (size > 0) {
        size_t part = size < 1024 * 1024 ? (size_t)size : 1024 * 1024;
        write_exact(output, buffer, part);
        size -= part;
    }
    free(buffer);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s SPARSE_INPUT BLOCK_DEVICE\n", argv[0]);
        return 2;
    }

    int input = open(argv[1], O_RDONLY | O_CLOEXEC);
    if (input < 0) {
        die("cannot open %s: %s", argv[1], strerror(errno));
    }
    int output = open(argv[2], O_WRONLY | O_CLOEXEC);
    if (output < 0) {
        die("cannot open %s: %s", argv[2], strerror(errno));
    }

    uint64_t target_size = 0;
    if (ioctl(output, BLKGETSIZE64, &target_size) != 0) {
        die("cannot read target size: %s", strerror(errno));
    }
    if (target_size != EXPECTED_TARGET_BYTES) {
        die("target is %" PRIu64 " bytes, expected %" PRIu64,
            target_size, EXPECTED_TARGET_BYTES);
    }

    struct sparse_header header;
    read_exact(input, &header, sizeof(header));
    if (header.magic != SPARSE_MAGIC || header.major_version != 1 ||
        header.file_hdr_sz < sizeof(header) ||
        header.chunk_hdr_sz < sizeof(struct chunk_header)) {
        die("unsupported sparse header");
    }
    uint64_t image_size = (uint64_t)header.blk_sz * header.total_blks;
    if (image_size != EXPECTED_IMAGE_BYTES || image_size > target_size ||
        header.blk_sz == 0 ||
        header.blk_sz % sizeof(uint32_t) != 0) {
        die("sparse image must be the guarded 8 GiB deployment image");
    }
    discard_exact(input, header.file_hdr_sz - sizeof(header));

    uint64_t output_blocks = 0;
    for (uint32_t index = 0; index < header.total_chunks; ++index) {
        struct chunk_header chunk;
        read_exact(input, &chunk, sizeof(chunk));
        discard_exact(input, header.chunk_hdr_sz - sizeof(chunk));

        if ((uint64_t)chunk.chunk_sz > header.total_blks - output_blocks) {
            die("chunk %u exceeds declared output geometry", index + 1);
        }
        uint64_t chunk_bytes = (uint64_t)chunk.chunk_sz * header.blk_sz;

        switch (chunk.chunk_type) {
        case CHUNK_RAW:
            if ((uint64_t)chunk.total_sz != header.chunk_hdr_sz + chunk_bytes) {
                die("raw chunk %u has an invalid size", index + 1);
            }
            copy_exact(input, output, chunk_bytes);
            break;
        case CHUNK_FILL: {
            if (chunk.total_sz != header.chunk_hdr_sz + sizeof(uint32_t)) {
                die("fill chunk %u has an invalid size", index + 1);
            }
            uint32_t pattern;
            read_exact(input, &pattern, sizeof(pattern));
            write_fill(output, pattern, chunk_bytes);
            break;
        }
        case CHUNK_DONT_CARE:
            if (chunk.total_sz != header.chunk_hdr_sz) {
                die("skip chunk %u has an invalid size", index + 1);
            }
            if (lseek(output, (off_t)chunk_bytes, SEEK_CUR) < 0) {
                die("cannot seek over chunk %u: %s", index + 1,
                    strerror(errno));
            }
            break;
        case CHUNK_CRC32:
            if (chunk.total_sz != header.chunk_hdr_sz + sizeof(uint32_t)) {
                die("CRC chunk %u has an invalid size", index + 1);
            }
            discard_exact(input, sizeof(uint32_t));
            break;
        default:
            die("chunk %u has unknown type 0x%04x", index + 1,
                chunk.chunk_type);
        }

        output_blocks += chunk.chunk_sz;
        if ((index + 1) % 512 == 0 || index + 1 == header.total_chunks) {
            fprintf(stderr, "sparse-write: chunk %u/%u, output blocks %" PRIu64
                    "/%u\n", index + 1, header.total_chunks, output_blocks,
                    header.total_blks);
        }
    }

    if (output_blocks != header.total_blks) {
        die("sparse stream produced %" PRIu64 " blocks, expected %u",
            output_blocks, header.total_blks);
    }
    if (fsync(output) != 0) {
        die("fsync failed: %s", strerror(errno));
    }
    close(output);
    close(input);
    puts("sparse-write: completed successfully");
    return 0;
}
