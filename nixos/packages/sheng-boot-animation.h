/* Native boot loop, sharing the exact SFB1 painter used by the generation menu.
 * Only the central composition and corner credit are refreshed. The console and display manager have
 * explicit ownership boundaries; animation never runs on top of another VT. */
#include <glob.h>
#include <linux/input.h>
#include <linux/kd.h>
#include <linux/vt.h>
#include <signal.h>

#define BOOT_FRAME_COUNT 60
#define BOOT_SIZE 720U
static volatile sig_atomic_t boot_stop;

struct boot_frame { uint8_t *data; size_t count; };

static void boot_signal(int signal_number) { (void)signal_number; boot_stop = 1; }

static int boot_control_write(const char *path, const char *value) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  if (fd < 0) return -1;
  size_t length = strlen(value);
  ssize_t written = write(fd, value, length);
  close(fd);
  return written == (ssize_t)length ? 0 : -1;
}

static int boot_marker_at(int directory, const char *name, const char *value) {
  int fd = openat(directory, name, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  if (fd < 0) return -1;
  size_t length = strlen(value);
  ssize_t written = write(fd, value, length);
  close(fd);
  return written == (ssize_t)length ? 0 : -1;
}

static void boot_details(const char *control) {
  char path[4096];
  if (snprintf(path, sizeof(path), "%s.disabled", control) < (int)sizeof(path))
    (void)boot_control_write(path, "details\n");
  int fd = open("/dev/tty3", O_RDWR | O_CLOEXEC);
  if (fd >= 0) {
    (void)ioctl(fd, KDSETMODE, KD_TEXT);
    (void)ioctl(fd, VT_ACTIVATE, 3);
    close(fd);
  }
}

static int boot_lock(const char *control, int create) {
  char path[4096];
  if (snprintf(path, sizeof(path), "%s.lock", control) >= (int)sizeof(path)) return -1;
  return open(path, O_RDWR | O_CLOEXEC | (create ? O_CREAT : 0), 0600);
}

static int boot_try_lock(int fd) {
  struct flock lock = { .l_type = F_WRLCK, .l_whence = SEEK_SET };
  return fcntl(fd, F_SETLK, &lock);
}

static int boot_request_stop(const char *control, int details) {
  int fd = boot_lock(control, 0);
  int saved_errno = errno;
  if (details) {
    char disabled[4096];
    if (snprintf(disabled, sizeof(disabled), "%s.disabled", control) >= (int)sizeof(disabled) ||
        boot_control_write(disabled, "details\n") < 0) { if (fd >= 0) close(fd); return 1; }
  }
  if (fd < 0) {
    if (details) boot_details(control);
    return saved_errno == ENOENT ? 0 : 1;
  }
  if (boot_control_write(control, details ? "details" : "stop") < 0) { close(fd); return 1; }
  struct timespec start;
  clock_gettime(CLOCK_MONOTONIC, &start);
  while (boot_try_lock(fd) < 0) {
    if ((errno != EACCES && errno != EAGAIN) || elapsed_ms(&start) > 3000) {
      close(fd); return 1;
    }
    struct timespec delay = {0, 10000000}; nanosleep(&delay, NULL);
  }
  if (details) boot_details(control);
  close(fd);
  return 0;
}

static int boot_load_frame(struct boot_frame *frame, const char *directory,
                           const char *phase, unsigned index, struct target *target) {
  char path[4096];
  unsigned span = target->width < target->height ? target->width : target->height;
  unsigned density = span >= 1600 ? 2 : 1;
  unsigned source_size = BOOT_SIZE * density;
  unsigned maximum_span = 800 * density;
  if (span > maximum_span) span = maximum_span;
  if (snprintf(path, sizeof(path), "%s/%s%s-%02u.sfb", directory, phase,
      density == 2 ? "-hd" : "", index) >= (int)sizeof(path)) return -1;
  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) return -1;
  struct stat status;
  if (fstat(fd, &status) < 0 || status.st_size < 16 ||
      status.st_size > (off_t)(4 + MAX_RECTANGLES * 12) || (status.st_size - 4) % 12) {
    close(fd); return -1;
  }
  size_t length = (size_t)status.st_size;
  frame->data = malloc(length);
  if (!frame->data) { close(fd); return -1; }
  size_t done = 0;
  while (done < length) {
    ssize_t got = read(fd, frame->data + done, length - done);
    if (got <= 0) { close(fd); return -1; }
    done += (size_t)got;
  }
  close(fd);
  if (memcmp(frame->data, COMMAND_MAGIC, 4)) return -1;
  frame->count = (length - 4) / 12;
  unsigned extent = BOOT_SIZE * span / 800;
  int credit = !strcmp(phase, "credit");
  unsigned ox = (target->width - extent) / (credit ? 1 : 2);
  unsigned oy = (target->height - extent) / (credit ? 1 : 2);
  for (size_t i = 0; i < frame->count; i++) {
    uint8_t *record = frame->data + 4 + i * 12;
    unsigned x = read_le16(record), y = read_le16(record + 2);
    unsigned w = read_le16(record + 4), h = read_le16(record + 6);
    if (record[11] || x + w > source_size || y + h > source_size || !w || !h) return -1;
    unsigned coordinates[4] = {ox + x * extent / source_size, oy + y * extent / source_size,
      (x + w) * extent / source_size - x * extent / source_size,
      (y + h) * extent / source_size - y * extent / source_size};
    for (unsigned c = 0; c < 4; c++) {
      record[c * 2] = coordinates[c] & 255;
      record[c * 2 + 1] = coordinates[c] >> 8;
    }
  }
  return 0;
}

static int boot_paint_frame(struct target *target, const struct boot_frame *frame,
                            const struct timespec *started_at, unsigned brightness) {
  if (prepare_surface(target, frame->data, frame->count) < 0) return -1;
  for (size_t i = 0; i < frame->count; i++) {
    uint8_t record[12]; memcpy(record, frame->data + 4 + i * 12, 12);
    for (unsigned c = 8; c < 11; c++) record[c] = record[c] * brightness / 10;
    if (paint_rectangle(target, record, started_at) < 0) return -1;
  }
  if (commit_surface(target, started_at) < 0) return -1;
  return 0;
}

static int boot_esc_pressed(int *fds, size_t *count, unsigned tick) {
  if (tick % 20 == 0) {
    glob_t paths = {0};
    if (glob("/dev/input/event*", 0, NULL, &paths) == 0 && paths.gl_pathc) {
      for (size_t i = 0; i < *count; i++) close(fds[i]);
      *count = 0;
      for (size_t i = 0; i < paths.gl_pathc && *count < 64; i++) {
        int fd = open(paths.gl_pathv[i], O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd >= 0) fds[(*count)++] = fd;
      }
    }
    globfree(&paths);
  }
  for (size_t i = 0; i < *count; i++) {
    struct input_event event;
    while (read(fds[i], &event, sizeof(event)) == sizeof(event))
      if (event.type == EV_KEY && event.code == KEY_ESC && event.value == 1) return 1;
  }
  return 0;
}

static int boot_animate(int argc, char **argv) {
  int testing = !strcmp(argv[1], "--animate-file") || !strcmp(argv[1], "--animate-file-handoff");
  int handoff = !strcmp(argv[1], "--animate-handoff") || !strcmp(argv[1], "--animate-file-handoff");
  if ((!testing && argc != 5) || (testing && argc != 12)) return 2;
  const char *directory = argv[testing ? 8 : 2];
  const char *phase = argv[testing ? 9 : 3];
  const char *control = argv[testing ? 10 : 4];
  if (strcmp(phase, "prepare") && strcmp(phase, "start")) return 2;
  unsigned max_frames = testing ? parse_number(argv[11], "frames") : 2400;
  if (!max_frames || max_frames > 2400) return 2;
  struct target target = { .fd = -1 };
  struct boot_frame frames[BOOT_FRAME_COUNT] = {{0}};
  struct boot_frame credit = {0};
  int lock_fd = -1, tty_fd = -1, result = 1, details = 0, owns_vt = 0;
  int control_fd = -1, directory_fd = -1, diagnostic_fd = -1;
  char parent[4096], ready_name[4096], disabled_name[4096];
  int input_fds[64]; size_t input_count = 0;
  char ready[4096], disabled[4096];
  if (snprintf(ready, sizeof(ready), "%s.ready", control) >= (int)sizeof(ready) ||
      snprintf(disabled, sizeof(disabled), "%s.disabled", control) >= (int)sizeof(disabled)) return 2;
  if (access(disabled, F_OK) == 0) return 0;
  /* Load the incoming generation while the initrd continues animating. Do not
   * retire the outgoing writer until every asset has been validated. */
  if (handoff) {
    int mapped = testing
      ? map_regular_target(&target, argv[2], parse_number(argv[3], "width"),
          parse_number(argv[4], "height"), parse_number(argv[5], "stride"), parse_number(argv[6], "bpp"))
      : map_framebuffer_target(&target, "/dev/fb0");
    if (mapped < 0) goto out;
    for (unsigned i = 0; i < BOOT_FRAME_COUNT; i++)
      if (boot_load_frame(&frames[i], directory, phase, i, &target) < 0) goto out;
    if (boot_load_frame(&credit, directory, "credit", 0, &target) < 0) goto out;
    if (boot_request_stop(control, 0) != 0) goto out;
    if (access(disabled, F_OK) == 0) { result = 0; goto out; }
  }
  lock_fd = boot_lock(control, 1);
  if (lock_fd < 0) goto out;
  if (boot_try_lock(lock_fd) < 0) { result = 75; goto out; }
  /* Open control state once. /run, /dev and /proc move during switch_root;
   * inherited directory/device descriptors remain valid across that handoff. */
  const char *slash = strrchr(control, '/');
  const char *basename = slash ? slash + 1 : control;
  size_t parent_length = slash ? (size_t)(slash - control) : 1;
  if (parent_length >= sizeof(parent)) goto out;
  if (slash) { memcpy(parent, control, parent_length); parent[parent_length] = 0; }
  else strcpy(parent, ".");
  if (!parent_length) strcpy(parent, "/");
  if (snprintf(ready_name, sizeof(ready_name), "%s.ready", basename) >= (int)sizeof(ready_name) ||
      snprintf(disabled_name, sizeof(disabled_name), "%s.disabled", basename) >= (int)sizeof(disabled_name)) goto out;
  directory_fd = open(parent, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (directory_fd < 0) goto out;
  unlinkat(directory_fd, ready_name, 0);
  if (boot_control_write(control, "run") < 0) goto out;
  control_fd = open(control, O_RDONLY | O_CLOEXEC);
  if (control_fd < 0) goto out;
  signal(SIGTERM, boot_signal); signal(SIGINT, boot_signal);
  if (!handoff && testing) {
    if (map_regular_target(&target, argv[2], parse_number(argv[3], "width"),
        parse_number(argv[4], "height"), parse_number(argv[5], "stride"),
        parse_number(argv[6], "bpp")) < 0) goto out;
    /* argv[7] is a frame output directory, or '-' for lifecycle-only tests. */
  } else if (!handoff) {
    for (int attempt = 0; attempt < 100 && !boot_stop; attempt++) {
      char request[16] = {0};
      if (pread(control_fd, request, sizeof(request)-1, 0) < 0) request[0] = 0;
      if (!strncmp(request, "stop", 4)) { result = 0; goto out; }
      if (!strncmp(request, "details", 7)) { result = 0; details = 1; goto out; }
      if (access("/dev/fb0", R_OK | W_OK) == 0) break;
      struct timespec delay = {0, 100000000}; nanosleep(&delay, NULL);
    }
    if (boot_stop) { result = 0; goto out; }
    if (map_framebuffer_target(&target, "/dev/fb0") < 0) { details = 1; goto out; }
  }
  target.row_buffer = malloc((size_t)target.width * target.bytes_per_pixel);
  if (!target.row_buffer) goto out;
  if (!handoff) {
    for (unsigned i = 0; i < BOOT_FRAME_COUNT; i++)
      if (boot_load_frame(&frames[i], directory, phase, i, &target) < 0) goto out;
    if (boot_load_frame(&credit, directory, "credit", 0, &target) < 0) goto out;
  }
  if (!testing) {
    diagnostic_fd = open("/dev/tty3", O_RDWR | O_CLOEXEC);
    tty_fd = open("/dev/tty2", O_RDWR | O_CLOEXEC);
    if (tty_fd < 0 || ioctl(tty_fd, KDSETMODE, KD_GRAPHICS) < 0 ||
        ioctl(tty_fd, VT_ACTIVATE, 2) < 0) goto out;
    owns_vt = 1;
    struct vt_stat state = {0};
    for (unsigned attempt = 0; attempt < 100 && !boot_stop; attempt++) {
      if (ioctl(tty_fd, VT_GETSTATE, &state) < 0) goto out;
      if (state.v_active == 2) break;
      struct timespec delay = {0, 10000000}; nanosleep(&delay, NULL);
    }
    if (boot_stop) { result = 0; goto out; }
    if (state.v_active != 2) goto out;
  }
  /* Paint black once, including any old menu outside the central composition. */
  for (unsigned y = 0; !handoff && y < target.height; y++)
    memset(target.map + (size_t)(y + target.yoffset) * target.stride +
      target.xoffset * target.bytes_per_pixel, 0, (size_t)target.width * target.bytes_per_pixel);
  struct timespec lifetime;
  clock_gettime(CLOCK_MONOTONIC, &lifetime);
  for (unsigned tick = 0; tick < max_frames && !boot_stop; tick++) {
    char request[16] = {0};
    if (pread(control_fd, request, sizeof(request)-1, 0) < 0) request[0] = 0;
    if (!strncmp(request, "details", 7)) { details = 1; break; }
    if (!strncmp(request, "stop", 4)) break;
    if (!testing) {
      struct vt_stat state;
      if (ioctl(tty_fd, VT_GETSTATE, &state) < 0 || state.v_active != 2) break;
      if (boot_esc_pressed(input_fds, &input_count, tick)) { details = 1; break; }
      if (elapsed_ms(&lifetime) >= 120000) { details = 1; break; }
    }
    struct timespec started_at;
    clock_gettime(CLOCK_MONOTONIC, &started_at);
    /* Keep both stages on the same monotonic timeline; skip late frames
     * instead of slowing the whole loop down under boot I/O load. */
    /* A one-frame file render is the deterministic menu/static preview oracle,
     * even when no separate frame-export directory was requested. */
    unsigned frame_index = testing && (strcmp(argv[7], "-") || max_frames == 1) ? tick % BOOT_FRAME_COUNT :
      ((uint64_t)started_at.tv_sec * 20 + started_at.tv_nsec / 50000000) % BOOT_FRAME_COUNT;
    struct boot_frame *frame = &frames[frame_index];
    unsigned brightness = !strcmp(phase, "prepare") && tick < 10 ? tick + 1 : 10;
    if (boot_paint_frame(&target, frame, &started_at, brightness) < 0 ||
        ((!tick || (!strcmp(phase, "prepare") && tick < 10)) &&
         boot_paint_frame(&target, &credit, &started_at, brightness) < 0)) goto out;
    if (!tick) {
      if (!testing) (void)ioctl(target.fd, FBIOBLANK, FB_BLANK_UNBLANK);
      char pid[32]; snprintf(pid, sizeof(pid), "%ld\n", (long)getpid());
      (void)boot_marker_at(directory_fd, ready_name, pid);
    }
    if (testing && strcmp(argv[7], "-")) {
      char path[4096];
      if (snprintf(path, sizeof(path), "%s/%03u.raw", argv[7], tick) >= (int)sizeof(path)) goto out;
      int output = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
      if (output < 0) goto out;
      size_t done = 0;
      while (done < target.map_length) {
        ssize_t written = write(output, target.map + done, target.map_length - done);
        if (written <= 0) { close(output); goto out; }
        done += (size_t)written;
      }
      close(output);
    }
    if (!testing || !strcmp(argv[7], "-")) {
      long remaining = 50 - elapsed_ms(&started_at);
      if (remaining > 0) { struct timespec delay = {0, remaining * 1000000}; nanosleep(&delay, NULL); }
    }
    if (!testing && tick + 1 == max_frames) details = 1;
  }
  result = 0;
out:
  for (size_t i = 0; i < input_count; i++) close(input_fds[i]);
  for (unsigned i = 0; i < BOOT_FRAME_COUNT; i++) free(frames[i].data);
  free(credit.data);
  if (tty_fd >= 0) {
    /* A normal handoff preserves graphics mode and the last frame. Only the
     * diagnostic path returns to text; toggling here exposed fbcon mid-boot. */
    if (owns_vt && (details || result)) (void)ioctl(tty_fd, KDSETMODE, KD_TEXT);
    close(tty_fd);
  }
  if (details || (!testing && result && result != 75)) {
    if (directory_fd >= 0) (void)boot_marker_at(directory_fd, disabled_name, "details");
    if (!testing) {
      if (diagnostic_fd >= 0) {
        (void)ioctl(diagnostic_fd, KDSETMODE, KD_TEXT);
        (void)ioctl(diagnostic_fd, VT_ACTIVATE, 3);
      } else boot_details(control);
    }
  }
  if (diagnostic_fd >= 0) close(diagnostic_fd);
  if (directory_fd >= 0) { unlinkat(directory_fd, ready_name, 0); close(directory_fd); }
  if (control_fd >= 0) close(control_fd);
  if (lock_fd >= 0) close(lock_fd);
  close_target(&target);
  return result;
}
