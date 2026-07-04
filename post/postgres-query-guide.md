---
title: "A Practical Guide to Writing Fast Postgres Queries"
date: 2026-07-04
---

Writing this down because I keep explaining the same handful of things whenever
someone shows me a slow query. Most slow queries aren't slow because Postgres is
slow. They're slow because the query is written in a way that stops Postgres from
using an index, or makes it do far more work than it needs to.

Here's a flat list of the most common pitfalls, and how to fix each one. I've
left out the rare stuff. These are the things that bite people every week.

### 1. Wrapping an indexed column in a function
If you put a column inside a function in the `WHERE` clause, Postgres can't use a
plain index on that column. It has to compute the function for every row.

```sql
-- Slow: index on created_at is ignored
WHERE date(created_at) = '2026-07-04'

-- Fast: leave the column alone, transform the value instead
WHERE created_at >= '2026-07-04' AND created_at < '2026-07-05'
```

If you genuinely need the function, create an expression index:
`CREATE INDEX ON orders (date(created_at));`

### 2. Leading wildcards in LIKE
A normal B-tree index can only help when Postgres knows the start of the string.

```sql
-- Slow: leading % means a full scan
WHERE email LIKE '%@gmail.com'

-- Fast: anchored prefix can use an index
WHERE email LIKE 'emil%'
```

For real "contains" or fuzzy search, use a trigram index:
`CREATE EXTENSION pg_trgm; CREATE INDEX ON users USING gin (email gin_trgm_ops);`

### 3. Mismatched types force a scan
If a column is `text` but you compare it to a number, or the other way around,
Postgres may cast every row and skip the index.

```sql
-- Slow if account_no is text: implicit cast on every row
WHERE account_no = 12345

-- Fast: match the column's actual type
WHERE account_no = '12345'
```

Fix the query. Better still, fix the column type so this can't happen again.

### 4. Column order in composite indexes matters
An index on `(status, created_at)` helps queries that filter on `status`, or on
`status` and `created_at` together. It does not help a query that filters only on
`created_at`.

My rule of thumb: put the column you filter by equality (`=`) first, and the
column you filter by range (`>`, `<`, `BETWEEN`) or sort by last.

```sql
-- Index (status, created_at) shines here
WHERE status = 'paid' AND created_at > now() - interval '7 days'
```

### 5. OR kills index usage
`OR` across different columns often can't use indexes well.

```sql
-- Slow
WHERE email = 'a@b.com' OR phone = '555-1234'

-- Fast: UNION lets each branch use its own index
SELECT * FROM users WHERE email = 'a@b.com'
UNION
SELECT * FROM users WHERE phone = '555-1234';
```

### 6. SELECT * when you don't need it
Selecting every column forces Postgres to fetch full rows from the table, even
when the answer is sitting right there in an index. Ask only for what you need.
It lets Postgres use an index-only scan and moves less data over the wire.

```sql
-- Reads the whole row
SELECT * FROM orders WHERE customer_id = 42;

-- Can be answered from an index on (customer_id, total)
SELECT total FROM orders WHERE customer_id = 42;
```

### 7. OFFSET pagination gets slower every page
`OFFSET 100000` means Postgres reads and throws away 100,000 rows before it gives
you anything. Deep pages crawl.

```sql
-- Slow on page 5000
ORDER BY id LIMIT 20 OFFSET 100000

-- Fast: remember the last id you saw ("keyset" pagination)
WHERE id > 100000 ORDER BY id LIMIT 20
```

### 8. Sorting without an index
`ORDER BY` on an unindexed column makes Postgres sort the whole result in memory,
or spill it to disk. An index that already stores rows in the right order skips
the sort entirely.

```sql
-- If you often do this:
ORDER BY created_at DESC LIMIT 20
-- Then create:
CREATE INDEX ON posts (created_at DESC);
```

This matters most with `LIMIT`. The index lets Postgres stop after 20 rows
instead of sorting millions.

### 9. Counting everything just to check existence
`COUNT(*)` scans every matching row. If you only want to know "does at least one
exist?", don't count.

```sql
-- Slow: counts every match
SELECT count(*) FROM orders WHERE user_id = 42;

-- Fast: stops at the first match
SELECT EXISTS (SELECT 1 FROM orders WHERE user_id = 42);
```

### 10. N+1 queries
Running one query per row in a loop is almost always slower than one query with a
join or an `IN` list. This usually sneaks in through an ORM.

```sql
-- Instead of 100 queries like this in a loop:
SELECT * FROM orders WHERE user_id = 1;

-- Fetch them all at once:
SELECT * FROM orders WHERE user_id = ANY('{1,2,3}');
```

### 11. Functions and casts breaking join conditions
The same rule as the first pitfall applies to joins. If you wrap the join column
in a function or a cast, the index on that column can't help.

```sql
-- Slow: cast on every row of the join
JOIN events e ON e.user_id::text = u.id::text

-- Fast: join on matching types, no casts
JOIN events e ON e.user_id = u.id
```

Make sure both sides of a join key are the same type and both are indexed.

### 12. NOT IN with a nullable column
If the subquery can return a `NULL`, `NOT IN` quietly returns zero rows. That's a
correctness bug, not just a slow query.

```sql
-- Dangerous: one NULL and you get nothing back
WHERE id NOT IN (SELECT parent_id FROM nodes)

-- Safe and usually faster
WHERE NOT EXISTS (
  SELECT 1 FROM nodes n WHERE n.parent_id = t.id
)
```

### 13. Filtering on the result of an aggregate
Use `WHERE` to filter rows before grouping, and `HAVING` only to filter the groups
themselves. Putting row-level conditions in `HAVING` makes Postgres aggregate rows
it's about to throw away.

```sql
-- Wasteful: filters after grouping
GROUP BY user_id HAVING user_id = 42

-- Better: filter first, then group
WHERE user_id = 42 GROUP BY user_id
```

### 14. Not looking at the query plan
When a query is slow, don't guess. Ask Postgres what it's actually doing:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;
```

Look for a `Seq Scan` on a big table where you expected an `Index Scan`. Also
watch for rows where the estimated count is wildly different from the actual
count. That usually means your statistics are stale, so run `ANALYZE your_table;`
to refresh them.

### 15. Forgetting to index foreign keys
Postgres creates an index for primary keys automatically, but not for foreign
keys. Joins and `ON DELETE CASCADE` on an unindexed foreign key end up doing full
table scans.

```sql
-- After adding a foreign key, add its index:
CREATE INDEX ON order_items (order_id);
```

None of this needs deep database internals. The common thread is simple. Keep
indexed columns bare in `WHERE` and `JOIN`, ask only for the rows and columns you
need, and check the query plan instead of guessing. Do that and most of your slow
queries fix themselves.
