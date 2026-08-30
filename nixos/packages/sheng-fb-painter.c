#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define COMMAND_MAGIC "SFB1"
#define COMMAND_HEADER_SIZE 4U
#define COMMAND_RECORD_SIZE 12U
#define MAX_RECTANGLES 10000U
#define RENDER_TIMEOUT_MS 3000L

struct target {
  int fd;
  uint8_t *map;
  uint8_t *surface;
  uint8_t *row_buffer;
  size_t map_length;
  size_t surface_stride;
  unsigned int width;
  unsigned int height;
  unsigned int stride;
  unsigned int bytes_per_pixel;
  unsigned int xoffset;
  unsigned int yoffset;
  struct fb_bitfield red;
  struct fb_bitfield green;
  struct fb_bitfield blue;
  unsigned int surface_x;
  unsigned int surface_y;
  unsigned int surface_width;
  unsigned int surface_height;
  int framebuffer;
};

static uint16_t read_le16(const uint8_t *data) {
  return (uint16_t)data[0] | ((uint16_t)data[1] << 8);
}

static long elapsed_ms(const struct timespec *start) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (now.tv_sec - start->tv_sec) * 1000L +
         (now.tv_nsec - start->tv_nsec) / 1000000L;
}

static uint32_t color_field(uint8_t value, struct fb_bitfield field) {
  uint32_t maximum;

  if (field.length == 0 || field.offset >= 32)
    return 0;
  maximum = field.length >= 32 ? UINT32_MAX : ((1U << field.length) - 1U);
  return (uint32_t)(((uint64_t)value * maximum / 255U) << field.offset);
}

static uint32_t pixel_value(const struct target *target, uint8_t red,
                            uint8_t green, uint8_t blue) {
  return color_field(red, target->red) |
         color_field(green, target->green) |
         color_field(blue, target->blue);
}

static void store_pixel(uint8_t *destination, uint32_t value,
                        unsigned int bytes_per_pixel) {
  unsigned int index;

  for (index = 0; index < bytes_per_pixel; index++)
    destination[index] = (uint8_t)(value >> (index * 8U));
}

static int paint_rectangle(struct target *target, const uint8_t *record,
                           const struct timespec *started_at) {
  unsigned int x = read_le16(record);
  unsigned int y = read_le16(record + 2);
  unsigned int width = read_le16(record + 4);
  unsigned int height = read_le16(record + 6);
  uint32_t value = pixel_value(target, record[8], record[9], record[10]);
  uint8_t *destination;
  size_t row_bytes;
  unsigned int column;
  unsigned int row;

  if (x >= target->width || y >= target->height || width == 0 || height == 0)
    return 0;
  if (width > target->width - x)
    width = target->width - x;
  if (height > target->height - y)
    height = target->height - y;

  destination = target->surface +
                (size_t)(y - target->surface_y) * target->surface_stride +
                (size_t)(x - target->surface_x) * target->bytes_per_pixel;
  row_bytes = (size_t)width * target->bytes_per_pixel;

  for (column = 0; column < width; column++)
    store_pixel(target->row_buffer +
                    (size_t)column * target->bytes_per_pixel,
                value,
                target->bytes_per_pixel);

  for (row = 0; row < height; row++) {
    memcpy(destination + (size_t)row * target->surface_stride,
           target->row_buffer, row_bytes);
    if ((row & 63U) == 0U && elapsed_ms(started_at) > RENDER_TIMEOUT_MS)
      return -1;
  }

  return elapsed_ms(started_at) > RENDER_TIMEOUT_MS ? -1 : 0;
}

static int map_regular_target(struct target *target, const char *path,
                              unsigned long width, unsigned long height,
                              unsigned long stride, unsigned long bpp) {
  struct stat status;
  size_t required;

  if (width == 0 || height == 0 || stride == 0 ||
      (bpp != 16 && bpp != 24 && bpp != 32)) {
    fprintf(stderr, "invalid file framebuffer geometry\n");
    return -1;
  }

  memset(target, 0, sizeof(*target));
  target->fd = open(path, O_RDWR | O_CLOEXEC);
  if (target->fd < 0) {
    perror(path);
    return -1;
  }
  target->width = (unsigned int)width;
  target->height = (unsigned int)height;
  target->stride = (unsigned int)stride;
  target->bytes_per_pixel = (unsigned int)(bpp / 8U);
  target->red.offset = bpp == 16 ? 11 : 16;
  target->red.length = bpp == 16 ? 5 : 8;
  target->green.offset = bpp == 16 ? 5 : 8;
  target->green.length = bpp == 16 ? 6 : 8;
  target->blue.offset = 0;
  target->blue.length = bpp == 16 ? 5 : 8;
  if ((size_t)target->width * target->bytes_per_pixel > target->stride) {
    fprintf(stderr, "file framebuffer stride is smaller than one visible row\n");
    close(target->fd);
    return -1;
  }
  required = (size_t)target->stride * target->height;

  if (fstat(target->fd, &status) < 0 || (size_t)status.st_size < required) {
    fprintf(stderr, "%s is smaller than the requested framebuffer\n", path);
    close(target->fd);
    return -1;
  }
  target->map_length = required;
  target->map = mmap(NULL, required, PROT_READ | PROT_WRITE, MAP_SHARED,
                     target->fd, 0);
  if (target->map == MAP_FAILED) {
    perror("mmap file framebuffer");
    close(target->fd);
    return -1;
  }
  return 0;
}

static int map_framebuffer_target(struct target *target, const char *path) {
  struct fb_fix_screeninfo fixed;
  struct fb_var_screeninfo variable;
  size_t required;

  memset(target, 0, sizeof(*target));
  target->fd = open(path, O_RDWR | O_CLOEXEC);
  if (target->fd < 0) {
    perror(path);
    return -1;
  }
  if (ioctl(target->fd, FBIOGET_FSCREENINFO, &fixed) < 0 ||
      ioctl(target->fd, FBIOGET_VSCREENINFO, &variable) < 0) {
    perror("query framebuffer");
    close(target->fd);
    return -1;
  }
  if (variable.bits_per_pixel != 16 && variable.bits_per_pixel != 24 &&
      variable.bits_per_pixel != 32) {
    fprintf(stderr, "unsupported framebuffer depth %u\n",
            variable.bits_per_pixel);
    close(target->fd);
    return -1;
  }

  target->width = variable.xres;
  target->height = variable.yres;
  target->stride = fixed.line_length;
  target->bytes_per_pixel = variable.bits_per_pixel / 8U;
  target->xoffset = variable.xoffset;
  target->yoffset = variable.yoffset;
  target->red = variable.red;
  target->green = variable.green;
  target->blue = variable.blue;
  target->framebuffer = 1;
  if ((size_t)(target->xoffset + target->width) * target->bytes_per_pixel >
      target->stride) {
    fprintf(stderr, "framebuffer stride is smaller than one visible row\n");
    close(target->fd);
    return -1;
  }
  required = (size_t)target->stride * (target->height + target->yoffset);
  target->map_length = fixed.smem_len;
  if (target->map_length < required) {
    fprintf(stderr, "framebuffer memory is smaller than its visible geometry\n");
    close(target->fd);
    return -1;
  }
  target->map = mmap(NULL, target->map_length, PROT_READ | PROT_WRITE,
                     MAP_SHARED, target->fd, 0);
  if (target->map == MAP_FAILED) {
    perror("mmap framebuffer");
    close(target->fd);
    return -1;
  }
  (void)ioctl(target->fd, FBIOBLANK, FB_BLANK_UNBLANK);
  return 0;
}

static void close_target(struct target *target) {
  if (target->map && target->map != MAP_FAILED)
    munmap(target->map, target->map_length);
  if (target->fd >= 0)
    close(target->fd);
  free(target->surface);
  free(target->row_buffer);
}

static int prepare_surface(struct target *target, const uint8_t *commands,
                           size_t count) {
  unsigned int min_x = target->width;
  unsigned int min_y = target->height;
  unsigned int max_x = 0;
  unsigned int max_y = 0;
  size_t index;
  unsigned int row;

  for (index = 0; index < count; index++) {
    const uint8_t *record = commands + COMMAND_HEADER_SIZE +
                            index * COMMAND_RECORD_SIZE;
    unsigned int x = read_le16(record);
    unsigned int y = read_le16(record + 2);
    unsigned int width = read_le16(record + 4);
    unsigned int height = read_le16(record + 6);

    if (x >= target->width || y >= target->height || width == 0 || height == 0)
      continue;
    if (width > target->width - x)
      width = target->width - x;
    if (height > target->height - y)
      height = target->height - y;
    if (x < min_x)
      min_x = x;
    if (y < min_y)
      min_y = y;
    if (x + width > max_x)
      max_x = x + width;
    if (y + height > max_y)
      max_y = y + height;
  }

  if (min_x >= max_x || min_y >= max_y) {
    fprintf(stderr, "framebuffer command list has no visible rectangles\n");
    return -1;
  }

  target->surface_x = min_x;
  target->surface_y = min_y;
  target->surface_width = max_x - min_x;
  target->surface_height = max_y - min_y;
  target->surface_stride =
      (size_t)target->surface_width * target->bytes_per_pixel;
  target->surface = malloc(target->surface_stride * target->surface_height);
  if (!target->surface) {
    perror("allocate framebuffer composition surface");
    return -1;
  }

  for (row = 0; row < target->surface_height; row++) {
    const uint8_t *source = target->map +
                            (size_t)(target->surface_y + row + target->yoffset) *
                                target->stride +
                            (size_t)(target->surface_x + target->xoffset) *
                                target->bytes_per_pixel;
    memcpy(target->surface + (size_t)row * target->surface_stride,
           source, target->surface_stride);
  }
  return 0;
}

static int commit_surface(struct target *target,
                          const struct timespec *started_at) {
  unsigned int row;

  for (row = 0; row < target->surface_height; row++) {
    uint8_t *destination = target->map +
                           (size_t)(target->surface_y + row + target->yoffset) *
                               target->stride +
                           (size_t)(target->surface_x + target->xoffset) *
                               target->bytes_per_pixel;
    memcpy(destination,
           target->surface + (size_t)row * target->surface_stride,
           target->surface_stride);
    if ((row & 63U) == 0U && elapsed_ms(started_at) > RENDER_TIMEOUT_MS)
      return -1;
  }
  return elapsed_ms(started_at) > RENDER_TIMEOUT_MS ? -1 : 0;
}

static unsigned long parse_number(const char *value, const char *name) {
  char *end = NULL;
  unsigned long result;

  errno = 0;
  result = strtoul(value, &end, 10);
  if (errno || !end || *end != '\0') {
    fprintf(stderr, "invalid %s: %s\n", name, value);
    exit(2);
  }
  return result;
}

int main(int argc, char **argv) {
  const char *command_path;
  struct target target;
  struct stat command_status;
  uint8_t *commands;
  size_t command_length;
  size_t count;
  size_t index;
  int command_fd;
  int result = 1;
  struct timespec started_at;

  target.fd = -1;
  target.map = NULL;
  target.surface = NULL;
  if (argc == 2) {
    command_path = argv[1];
    if (map_framebuffer_target(&target, "/dev/fb0") < 0)
      return 1;
  } else if (argc == 8 && strcmp(argv[1], "--file") == 0) {
    command_path = argv[7];
    if (map_regular_target(&target, argv[2],
                           parse_number(argv[3], "width"),
                           parse_number(argv[4], "height"),
                           parse_number(argv[5], "stride"),
                           parse_number(argv[6], "bpp")) < 0)
      return 1;
  } else {
    fprintf(stderr,
            "usage: %s COMMANDS\n"
            "       %s --file FRAMEBUFFER WIDTH HEIGHT STRIDE BPP COMMANDS\n",
            argv[0], argv[0]);
    return 2;
  }
  target.row_buffer = malloc((size_t)target.width * target.bytes_per_pixel);
  if (!target.row_buffer) {
    perror("allocate framebuffer row buffer");
    close_target(&target);
    return 1;
  }

  command_fd = open(command_path, O_RDONLY | O_CLOEXEC);
  if (command_fd < 0) {
    perror(command_path);
    goto out;
  }
  if (fstat(command_fd, &command_status) < 0) {
    perror(command_path);
    close(command_fd);
    goto out;
  }
  command_length = (size_t)command_status.st_size;
  if (command_length < COMMAND_HEADER_SIZE ||
      (command_length - COMMAND_HEADER_SIZE) % COMMAND_RECORD_SIZE != 0) {
    fprintf(stderr, "invalid framebuffer command length\n");
    close(command_fd);
    goto out;
  }
  count = (command_length - COMMAND_HEADER_SIZE) / COMMAND_RECORD_SIZE;
  if (count == 0 || count > MAX_RECTANGLES) {
    fprintf(stderr, "invalid framebuffer rectangle count: %zu\n", count);
    close(command_fd);
    goto out;
  }
  commands = mmap(NULL, command_length, PROT_READ, MAP_PRIVATE, command_fd, 0);
  close(command_fd);
  if (commands == MAP_FAILED) {
    perror("mmap framebuffer commands");
    goto out;
  }
  if (memcmp(commands, COMMAND_MAGIC, COMMAND_HEADER_SIZE) != 0) {
    fprintf(stderr, "invalid framebuffer command magic\n");
    munmap(commands, command_length);
    goto out;
  }

  clock_gettime(CLOCK_MONOTONIC, &started_at);
  if (prepare_surface(&target, commands, count) < 0) {
    munmap(commands, command_length);
    goto out;
  }
  for (index = 0; index < count; index++) {
    const uint8_t *record = commands + COMMAND_HEADER_SIZE +
                            index * COMMAND_RECORD_SIZE;
    if (paint_rectangle(&target, record, &started_at) < 0) {
      fprintf(stderr, "framebuffer render exceeded %ld ms\n",
              RENDER_TIMEOUT_MS);
      munmap(commands, command_length);
      result = 124;
      goto out;
    }
  }
  if (commit_surface(&target, &started_at) < 0) {
    fprintf(stderr, "framebuffer commit exceeded %ld ms\n",
            RENDER_TIMEOUT_MS);
    munmap(commands, command_length);
    result = 124;
    goto out;
  }
  munmap(commands, command_length);
  __sync_synchronize();
  if (target.framebuffer)
    (void)ioctl(target.fd, FBIOBLANK, FB_BLANK_UNBLANK);
  result = 0;

out:
  close_target(&target);
  return result;
}
