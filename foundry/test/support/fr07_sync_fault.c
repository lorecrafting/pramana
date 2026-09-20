#include <string.h>
#include "sqlite3ext.h"
SQLITE_EXTENSION_INIT1

static sqlite3_file *target_file = 0;
static const sqlite3_io_methods *original_methods = 0;
static sqlite3_io_methods shim_methods;
static int armed = 0;
static int hit_count = 0;
static int observed_flags = 0;
static int returned_code = 0;
static int write_count = 0;
static int sequence = 0;
static int last_write_sequence = 0;
static int sync_sequence = 0;

static int fr07_xwrite(sqlite3_file *file, const void *buffer, int amount, sqlite3_int64 offset) {
  int rc = original_methods->xWrite(file, buffer, amount, offset);
  if (file == target_file && rc == SQLITE_OK) {
    write_count += 1;
    last_write_sequence = ++sequence;
  }
  return rc;
}

static int fr07_xsync(sqlite3_file *file, int flags) {
  if (file == target_file && armed) {
    armed = 0;
    hit_count += 1;
    observed_flags = flags;
    returned_code = SQLITE_IOERR_FSYNC;
    sync_sequence = ++sequence;
    return SQLITE_IOERR_FSYNC;
  }

  return original_methods->xSync(file, flags);
}

static void fr07_arm(sqlite3_context *context, int argc, sqlite3_value **argv) {
  (void)argc;
  (void)argv;
  sqlite3 *db = sqlite3_context_db_handle(context);
  sqlite3_file *file = 0;
  int rc = sqlite3_file_control(db, "main", SQLITE_FCNTL_JOURNAL_POINTER, &file);

  if (rc != SQLITE_OK || file == 0 || file->pMethods == 0 || file->pMethods->xSync == 0) {
    sqlite3_result_error_code(context, rc == SQLITE_OK ? SQLITE_ERROR : rc);
    return;
  }

  if (target_file != 0 && target_file != file) {
    sqlite3_result_error(context, "sync shim already targets another file", -1);
    return;
  }

  if (target_file == 0) {
    target_file = file;
    original_methods = file->pMethods;
    memcpy(&shim_methods, original_methods, sizeof(sqlite3_io_methods));
    shim_methods.xWrite = fr07_xwrite;
    shim_methods.xSync = fr07_xsync;
    file->pMethods = &shim_methods;
  }

  hit_count = 0;
  observed_flags = 0;
  returned_code = 0;
  write_count = 0;
  sequence = 0;
  last_write_sequence = 0;
  sync_sequence = 0;
  armed = 1;
  sqlite3_result_int(context, 1);
}

static void fr07_disarm(sqlite3_context *context, int argc, sqlite3_value **argv) {
  (void)argc;
  (void)argv;
  armed = 0;

  if (target_file != 0 && target_file->pMethods == &shim_methods) {
    target_file->pMethods = original_methods;
  }

  target_file = 0;
  original_methods = 0;
  sqlite3_result_int(context, 1);
}

static void fr07_hits(sqlite3_context *context, int argc, sqlite3_value **argv) {
  (void)argc;
  (void)argv;
  sqlite3_result_int(context, hit_count);
}

static void fr07_flags(sqlite3_context *context, int argc, sqlite3_value **argv) {
  (void)argc;
  (void)argv;
  sqlite3_result_int(context, observed_flags);
}

static void fr07_code(sqlite3_context *context, int argc, sqlite3_value **argv) {
  (void)argc;
  (void)argv;
  sqlite3_result_int(context, returned_code);
}

static void fr07_writes(sqlite3_context *context, int argc, sqlite3_value **argv) {
  (void)argc;
  (void)argv;
  sqlite3_result_int(context, write_count);
}

static void fr07_write_sequence(sqlite3_context *context, int argc, sqlite3_value **argv) {
  (void)argc;
  (void)argv;
  sqlite3_result_int(context, last_write_sequence);
}

static void fr07_sync_sequence(sqlite3_context *context, int argc, sqlite3_value **argv) {
  (void)argc;
  (void)argv;
  sqlite3_result_int(context, sync_sequence);
}

#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_fr07syncfault_init(
    sqlite3 *db,
    char **error_message,
    const sqlite3_api_routines *api) {
  (void)error_message;
  SQLITE_EXTENSION_INIT2(api);

  int rc = sqlite3_create_function(db, "fr07_sync_arm", 0, SQLITE_UTF8, 0, fr07_arm, 0, 0);
  if (rc == SQLITE_OK)
    rc = sqlite3_create_function(db, "fr07_sync_disarm", 0, SQLITE_UTF8, 0, fr07_disarm, 0, 0);
  if (rc == SQLITE_OK)
    rc = sqlite3_create_function(db, "fr07_sync_hits", 0, SQLITE_UTF8 | SQLITE_DETERMINISTIC, 0, fr07_hits, 0, 0);
  if (rc == SQLITE_OK)
    rc = sqlite3_create_function(db, "fr07_sync_flags", 0, SQLITE_UTF8 | SQLITE_DETERMINISTIC, 0, fr07_flags, 0, 0);
  if (rc == SQLITE_OK)
    rc = sqlite3_create_function(db, "fr07_sync_code", 0, SQLITE_UTF8 | SQLITE_DETERMINISTIC, 0, fr07_code, 0, 0);
  if (rc == SQLITE_OK)
    rc = sqlite3_create_function(db, "fr07_sync_writes", 0, SQLITE_UTF8 | SQLITE_DETERMINISTIC, 0, fr07_writes, 0, 0);
  if (rc == SQLITE_OK)
    rc = sqlite3_create_function(db, "fr07_write_sequence", 0, SQLITE_UTF8 | SQLITE_DETERMINISTIC, 0, fr07_write_sequence, 0, 0);
  if (rc == SQLITE_OK)
    rc = sqlite3_create_function(db, "fr07_sync_sequence", 0, SQLITE_UTF8 | SQLITE_DETERMINISTIC, 0, fr07_sync_sequence, 0, 0);

  return rc;
}
