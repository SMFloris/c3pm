module sqlite_example;

import sqlite3;
import std::io;

const String DB_PATH = "todos.db";

fn void print_usage()
{
	io::printn(
		"Usage:\n"
		"  sqlite_example add <note>\n"
		"  sqlite_example list"
	);
}

fn int sqlite_error(sqlite3::SqliteHandle db, String operation)
{
	io::printfn("sqlite_example: %s: %s", operation, sqlite3::errmsg(db));
	return 1;
}

fn int main(String[] args)
{
	if (args.len < 2)
	{
		print_usage();
		return 2;
	}

	sqlite3::SqliteHandle db;
	if (sqlite3::open(DB_PATH, &db) != sqlite3::SqliteResult.OK)
	{
		return sqlite_error(db, "cannot open todos.db");
	}
	defer (void)sqlite3::close(db);

	if (sqlite3::exec(db,
		"CREATE TABLE IF NOT EXISTS todos ("
		"id INTEGER PRIMARY KEY AUTOINCREMENT, "
		"note TEXT NOT NULL"
		");", null, null, null) != sqlite3::SqliteResult.OK)
	{
		return sqlite_error(db, "cannot initialize schema");
	}

	if (args[1] == "add")
	{
		if (args.len != 3)
		{
			print_usage();
			return 2;
		}
		sqlite3::SqliteStmt statement;
		if (sqlite3::prepare_v2(db, "INSERT INTO todos (note) VALUES (?1);",
			-1, &statement, null) != sqlite3::SqliteResult.OK)
		{
			return sqlite_error(db, "cannot prepare insert");
		}
		defer (void)sqlite3::finalize(statement);
		if (sqlite3::bind_text(statement, 1, args[2].zstr_tcopy(), -1, null)
			!= sqlite3::SqliteResult.OK)
		{
			return sqlite_error(db, "cannot bind note");
		}
		if (sqlite3::step(statement) != sqlite3::SqliteResult.DONE)
		{
			return sqlite_error(db, "cannot add note");
		}
		io::printfn("Added: %s", args[2]);
		return 0;
	}

	if (args[1] == "list")
	{
		if (args.len != 2)
		{
			print_usage();
			return 2;
		}
		sqlite3::SqliteStmt statement;
		if (sqlite3::prepare_v2(db, "SELECT id, note FROM todos ORDER BY id;",
			-1, &statement, null) != sqlite3::SqliteResult.OK)
		{
			return sqlite_error(db, "cannot prepare list");
		}
		defer (void)sqlite3::finalize(statement);
		sqlite3::SqliteResult result;
		while ((result = sqlite3::step(statement)) == sqlite3::SqliteResult.ROW)
		{
			io::printfn("%d\t%s", sqlite3::column_int(statement, 0),
				sqlite3::column_text(statement, 1));
		}
		if (result != sqlite3::SqliteResult.DONE)
		{
			return sqlite_error(db, "cannot list notes");
		}
		return 0;
	}

	print_usage();
	return 2;
}
