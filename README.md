# ZenC PostgreSQL Driver

A high-level PostgreSQL client library for the [ZenC programming language](https://github.com/zenc-lang/zenc), wrapping `libpq` with an ergonomic, memory-safe API.

> Write modern, safe database code like a high-level language, link and run on bare C.

---

## Features

- **Simple, ergonomic API** — `PgConnection::new()`, `conn.query()`, `conn.exec()`
- **Memory-safe by default** — `Drop` implementations automatically call `PQfinish` and `PQclear`
- **ZenC-native error handling** — Returns `Result<T>` instead of raw error codes
- **No build system required** — Uses ZenC's built-in `//> link:` directive
- **Lightweight wrapper** — Thin abstraction over `libpq` with zero runtime overhead

---

## Prerequisites

1. **ZenC compiler** (`zc`) — [Installation guide](https://github.com/zenc-lang/zenc#quick-start)
2. **PostgreSQL client libraries** (`libpq`):

   ```bash
   # Arch Linux
   sudo pacman -S postgresql-libs

   # Ubuntu / Debian
   sudo apt-get install libpq-dev

   # Fedora / RHEL
   sudo dnf install postgresql-devel

   # macOS
   brew install libpq
   ```

---

## Project Structure

```
pg/
├── sys.zc   # Low-level C interop layer (raw libpq bindings)
└── pg.zc    # High-level ZenC wrapper (PgConnection, PgResult)
```

You only need to import `pg/pg.zc` in your application code.

---

## Quick Start

Add the link directive and import the module:

```zc
//> link: -lpq

import "std/io.zc"
import "./pg/pg.zc"

fn main() {
    let conninfo = "host=localhost dbname=postgres user=postgres";
    let conn_res = PgConnection::new(conninfo);

    if (conn_res.is_err()) {
        println "Failed to connect: {conn_res.err}";
        return;
    }

    let conn = conn_res.unwrap();

    // Create a table
    let create = conn.exec(
        "CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name TEXT)"
    );
    if (create.is_err()) {
        println "CREATE failed: {create.err}";
        return;
    }

    // Insert data
    let insert = conn.exec(
        "INSERT INTO users (name) VALUES ('Alice'), ('Bob')"
    );
    if (insert.is_err()) {
        println "INSERT failed: {insert.err}";
        return;
    }

    // Query data
    let query_res = conn.query("SELECT id, name FROM users");
    if (query_res.is_err()) {
        println "SELECT failed: {query_res.err}";
        return;
    }

    let result = query_res.unwrap();
    println "Rows: {result.row_count()}, Columns: {result.column_count()}";

    for (let i = 0; i < result.row_count(); i = i + 1) {
        let id   = result.get(i, 0).unwrap();
        let name = result.get(i, 1).unwrap();
        println "{id} | {name}";
        id.destroy();
        name.destroy();
    }
}
```

Compile and run:

```bash
zc run main.zc
```

Or build an executable:

```bash
zc build main.zc -o myapp
./myapp
```

---

## API Reference

### `PgConnection`

Represents an open connection to a PostgreSQL server.

| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `fn new(conninfo: char*) -> Result<PgConnection>` | Opens a connection using a libpq connection string |
| `query` | `fn query(self, sql: char*) -> Result<PgResult>` | Executes a SQL query that returns rows (e.g. `SELECT`) |
| `exec` | `fn exec(self, sql: char*) -> Result<bool>` | Executes a SQL command with no result set (e.g. `CREATE`, `INSERT`) |
| `query_params` | `fn query_params(self, sql: char*, params: char**, nParams: c_int) -> Result<PgResult>` | Executes a parameterized query (e.g. `SELECT ... WHERE x = $1`) |
| `exec_params` | `fn exec_params(self, sql: char*, params: char**, nParams: c_int) -> Result<bool>` | Executes a parameterized command (e.g. `INSERT ... VALUES ($1, $2)`) |
| `last_error` | `fn last_error(self) -> String` | Returns the last libpq error message |

**Connection string examples:**

```zc
"host=localhost dbname=mydb user=myuser password=secret"
"host=/var/run/postgresql dbname=mydb user=myuser"
"postgresql://myuser:secret@localhost:5432/mydb"
```

### `PgResult`

Represents the result of a `query()` call.

| Method | Signature | Description |
|--------|-----------|-------------|
| `row_count` | `fn row_count(self) -> c_int` | Number of rows in the result |
| `column_count` | `fn column_count(self) -> c_int` | Number of columns in the result |
| `get` | `fn get(self, row: c_int, col: c_int) -> Option<String>` | Returns the value at `(row, col)` as an `Option<String>` — `None` for SQL `NULL` |
| `column_name` | `fn column_name(self, col: c_int) -> String` | Returns the name of the given column |

### `Transaction`

Represents an active database transaction. Created via `PgConnection::begin()`.

| Method | Signature | Description |
|--------|-----------|-------------|
| `commit` | `fn commit(self) -> Result<bool>` | Commits the transaction |
| `rollback` | `fn rollback(self) -> Result<bool>` | Rolls back the transaction |
| `exec` | `fn exec(self, sql: char*) -> Result<bool>` | Executes a SQL command inside the transaction |
| `query` | `fn query(self, sql: char*) -> Result<PgResult>` | Executes a query inside the transaction |
| `exec_params` | `fn exec_params(self, sql: char*, params: char**, nParams: c_int) -> Result<bool>` | Parameterized command inside the transaction |
| `query_params` | `fn query_params(self, sql: char*, params: char**, nParams: c_int) -> Result<PgResult>` | Parameterized query inside the transaction |
| `last_error` | `fn last_error(self) -> String` | Returns the last libpq error message |

> **Note:** The `PgConnection` used to start the transaction must outlive the `Transaction` object. Dropping a `Transaction` without calling `commit()` or `rollback()` automatically issues `ROLLBACK`.

---

## Error Handling

All database operations return `Result<T>`:

```zc
let res = conn.exec("DELETE FROM users WHERE id = 99");
if (res.is_err()) {
    println "Delete failed: {res.err}";
} else {
    println "Delete succeeded";
}
```

To inspect the underlying `libpq` error after a failure, use `last_error()`:

```zc
let conn_res = PgConnection::new("host=badhost dbname=test");
if (conn_res.is_err()) {
    println "Connection error: {conn_res.err}";
    // libpq-specific detail is not available here because
    // the connection handle is already cleaned up.
}
```

---

## Memory Management

Both `PgConnection` and `PgResult` implement `Drop`, so resources are freed automatically when they go out of scope:

```zc
{
    let conn = PgConnection::new("...").unwrap();
    let res = conn.query("SELECT * FROM users").unwrap();
    // PQclear(res) and PQfinish(conn) are called automatically here
}
```

**String lifetimes:** `PgResult::get()` returns an `Option<String>` and `PgResult::column_name()` returns an owned `String`. You must call `.destroy()` on the unwrapped `String` values when done, or let them fall out of scope.

```zc
let maybe_name = result.get(0, 1);
if (maybe_name.is_some()) {
    let name = maybe_name.unwrap();
    println "Name: {name}";
    name.destroy();
} else {
    println "Name is NULL";
}
```

---

## Build Directive

The `//> link: -lpq` directive at the top of your entry file tells the ZenC compiler to link against `libpq` automatically. No Makefile required.

If `libpq-fe.h` is in a non-standard location (e.g. macOS Homebrew), add:

```zc
//> include: /opt/homebrew/opt/libpq/include
//> lib: /opt/homebrew/opt/libpq/lib
//> link: -lpq
```

---

## Examples

### Checking for NULL values

```zc
let maybe_value = result.get(0, 2);
if (maybe_value.is_none()) {
    println "Value is NULL";
} else {
    let value = maybe_value.unwrap();
    println "Value: {value}";
    value.destroy();
}
```

### Getting column names dynamically

```zc
for (let c = 0; c < result.column_count(); c = c + 1) {
    let col_name = result.column_name(c);
    println "Column {c}: {col_name}";
    col_name.destroy();
}
```

### Conditional logic with multiple statements

```zc
let conn = PgConnection::new("host=localhost dbname=shop").unwrap();

let r1 = conn.exec("BEGIN");
let r2 = conn.exec("UPDATE inventory SET qty = qty - 1 WHERE id = 42");
let r3 = conn.exec("COMMIT");

if (r1.is_ok() && r2.is_ok() && r3.is_ok()) {
    println "Transaction committed";
} else {
    conn.exec("ROLLBACK");
    println "Transaction rolled back";
}
```

### Transactions

Use the `Transaction` struct for safer transaction handling with automatic rollback on drop:

```zc
let conn = PgConnection::new("host=localhost dbname=shop").unwrap();

let tx_res = conn.begin();
if (tx_res.is_err()) {
    println "BEGIN failed: {tx_res.err}";
    return;
}
let tx = tx_res.unwrap();

let r1 = tx.exec("UPDATE inventory SET qty = qty - 1 WHERE id = 42");
let r2 = tx.exec("INSERT INTO orders (item_id) VALUES (42)");

if (r1.is_ok() && r2.is_ok()) {
    tx.commit();
    println "Transaction committed";
} else {
    tx.rollback();
    println "Transaction rolled back";
}
```

### Parameterized queries

Use `exec_params` and `query_params` to pass values safely without manual escaping:

```zc
let conn = PgConnection::new("host=localhost dbname=shop").unwrap();

let params = ["Alice", "30"];
let insert = conn.exec_params(
    "INSERT INTO users (name, age) VALUES ($1, $2)",
    params, 2
);

let query_params = ["Alice"];
let res = conn.query_params(
    "SELECT id, name, age FROM users WHERE name = $1",
    query_params, 1
).unwrap();

println "Rows: {res.row_count()}";
```

---

## Testing

### Running the Test Suite

This project includes an integration test suite in the `tests/` directory.

1. Ensure you have a PostgreSQL server running on `localhost`.
2. (Optional) Set the `ZENC_PG_TEST_CONNINFO` environment variable if your server uses non-default credentials:

   ```bash
   export ZENC_PG_TEST_CONNINFO="host=localhost dbname=postgres user=postgres password=secret"
   ```
3. Run all tests:

   ```bash
   ./run_tests.sh
   ```

Or run individual test files directly:

```bash
zc run tests/test_connection.zc
zc run tests/test_query.zc
zc run tests/test_null.zc
```

### Running the Demo

```bash
zc run main.zc
```

If no server is available, the tests and demo will report connection errors.

---

## Future Work

- [x] **Parameterized queries** — `PQexecParams` wrapper for safe value binding
- [x] **Transactions** — Dedicated `Transaction` struct with `commit()` / `rollback()`
- [ ] **Async support** — Integration with ZenC's `async` / `await`
- [ ] **Connection pooling** — Simple pool for concurrent workloads
- [ ] **Iterator interface** — Row-by-row iteration over `PgResult`
- [x] **Better NULL handling** — Return `Option<String>` instead of empty strings

---

## License

This wrapper is provided as-is for use in ZenC projects. It links against PostgreSQL's `libpq`, which is licensed under the [PostgreSQL License](https://www.postgresql.org/about/licence/).
