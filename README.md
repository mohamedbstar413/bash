# 🗄️ Bash Database Management System

A lightweight, SQL-like database management system implemented entirely in Bash scripting. This project demonstrates advanced shell scripting techniques to create a functional DBMS with support for multiple databases, tables, and SQL-like operations.

---

## ✨ Features

### Database Operations
- **Create Database** - Initialize new database instances
- **Drop Database** - Remove databases and all associated tables
- **Use Database** - Switch between different databases
- **Show Databases** - List all available databases

### Table Operations
- **Create Table** - Define tables with custom schemas
- **Drop Table** - Remove tables from the database
- **Describe Table** - View table structure and metadata
- **Show Tables** - List all tables in the current database

### Data Manipulation
- **INSERT** - Add new records to tables
- **SELECT** - Query data with optional WHERE clauses
- **UPDATE** - Modify existing records
- **DELETE** - Remove records from tables

### Advanced Features
- **Primary Key Constraints** - Enforce uniqueness on key fields
- **Data Types** - Support for `int`, `string`, and `boolean` types
- **WHERE Clauses** - Filter operations with conditional logic
- **JOIN Operations** - Combine data from multiple tables
- **Aggregation Functions** - `COUNT`, `MAX`, `MIN`, `SUM`, `AVG` with GROUP BY
- **File Locking** - Thread-safe write operations using `flock`

---

## 🚀 Getting Started

### Prerequisites
- Bash 4.0 or higher
- Linux/Unix environment
- Extended pattern matching support (`shopt -s extglob`)

### Installation

1. Clone or download the script:
```bash
chmod +x dbms.sh
```

2. Run the database management system:
```bash
./dbms.sh
```

---

## 📖 Usage Guide

### Basic Syntax

The prompt accepts SQL-like commands ending with semicolons (`;`). Multi-line commands are supported.

```
-> <your command here>;
```

### Command Examples

#### Database Management

```sql
-- Create a new database
CREATE DATABASE mydb;

-- Show all databases
SHOW DATABASES;

-- Select a database to use
USE mydb;

-- Drop a database
DROP DATABASE mydb;
```

#### Table Creation

```sql
-- Create a table with various data types
CREATE TABLE users (
    id int PK,
    name string,
    age int,
    active boolean
);

-- Show all tables in current database
SHOW TABLES;

-- View table structure
DESCRIBE users;

-- Drop a table
DROP TABLE users;
```

#### Data Insertion

```sql
-- Insert with all fields
INSERT INTO users VALUES (1, john, 25, 1);

-- Insert with specific fields
INSERT INTO users (id, name) VALUES (2, jane);
```

#### Data Selection

```sql
-- Select all records
SELECT * FROM users;

-- Select specific columns
SELECT name, age FROM users;

-- Select with WHERE clause
SELECT * FROM users WHERE age=25;

-- Select specific columns with condition
SELECT name FROM users WHERE active=1;
```

#### Data Modification

```sql
-- Update records
UPDATE users SET age=26 WHERE id=1;

-- Delete records
DELETE FROM users WHERE id=2;

-- Delete all records
DELETE FROM users;
```

#### Advanced Queries

**JOIN Operations:**
```sql
-- Inner join on two tables
SELECT users.name, orders.product 
FROM users 
JOIN orders 
ON users.id=orders.user_id;

-- Select all columns from joined tables
SELECT * FROM users JOIN orders ON users.id=orders.user_id;
```

**Aggregation with GROUP BY:**
```sql
-- Count records by group
SELECT COUNT(*) FROM sales GROUP BY region;

-- Maximum value by group
SELECT MAX(amount) FROM sales GROUP BY region;

-- Multiple aggregations
SELECT COUNT(*), SUM(amount) FROM sales GROUP BY region;
```

---

## 🏗️ Architecture

### Data Storage
- **Databases** - Stored as directories in the file system
- **Tables** - Represented as text files with colon-separated values (`:`)
- **Metadata** - Schema information stored in hidden files (`.tablename`)
- **Database Registry** - `.db` file tracks all tables in a database

### File Structure
```
project_root/
├── dbms.sh                 # Main script
├── database1/              # Database directory
│   ├── .db                 # Table registry
│   ├── .users              # User table metadata
│   ├── users               # User table data
│   └── .orders             # Orders table metadata
└── database1_lock          # Lock file for safe writes
```

### Data Format

**Metadata files** (`.tablename`):
```
fieldname:datatype:constraint
id:int:PK
name:string:
age:int:
```

**Data files** (records):
```
value1:value2:value3
1:john:25
2:jane:30
```

---

## 🔒 Concurrency Control

The system implements file locking using `flock` to ensure data integrity during concurrent write operations:

```bash
exec 200>"${cur_db}_lock"
flock 200 sh -c "echo \"$output\" >> \"$cur_db/$table_to_insert\""
```

---

## ⚙️ Technical Highlights

### Pattern Matching
- Extensive use of Bash extended globbing patterns
- Case-insensitive SQL command matching using `@(pattern)` syntax
- Regex-based parsing with `BASH_REMATCH`

### Data Processing
- AWK for complex field manipulation and aggregation
- `sort` and `join` commands for JOIN operations
- `cut`, `grep`, and `sed` for text processing

### Validation
- Data type checking (int, string, boolean)
- Primary key uniqueness enforcement
- Field existence validation
- Syntax validation for SQL-like commands

---

## 🛠️ Supported Data Types

| Type | Description | Example |
|------|-------------|---------|
| `int` | Integer numbers | `42`, `1000` |
| `string` | Alphanumeric text | `john`, `hello_world` |
| `boolean` | Binary values | `0` (false), `1` (true) |

---

## 📋 Constraints

- **Primary Key (PK)** - Ensures unique values for a field
- Only one primary key allowed per table
- Primary key fields cannot be null
- Duplicate primary key values are rejected

---

## 🎯 Limitations

- No support for NULL values
- Limited to basic data types
- No support for foreign key constraints
- No transaction support (beyond file locking)
- No support for complex expressions in WHERE clauses
- Limited to equality operators in conditions
- Case-sensitive field and table names

---

## 🔚 Exit

To exit the database management system:
```sql
EX;
```

---

## 📝 Notes

- All commands must end with a semicolon (`;`)
- Field names must start with a letter
- Table names cannot start with numbers
- Multi-line commands are supported - press Enter to continue
- String values in INSERT statements don't require quotes
- Column values are separated by colons (`:`) in storage

---

## 🤝 Contributing

This project demonstrates educational concepts in:
- Shell scripting and Bash programming
- Database management system design
- File-based data storage
- SQL query parsing
- Concurrent access control

Feel free to extend functionality or optimize existing features!

---

## 📄 License

This project is provided as-is for educational purposes.

---

**Built with ❤️ using pure Bash scripting**
