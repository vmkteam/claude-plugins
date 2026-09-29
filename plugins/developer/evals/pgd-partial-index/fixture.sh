#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs
cat > docs/shop.pgd <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<pgd version="1" pg-version="18" default-schema="public">
  <project name="shop"></project>
  <database name="shop" encoding="UTF8"></database>
  <schema name="public">
    <table name="users">
      <column name="id" type="bigint" nullable="false">
        <identity generated="always"></identity>
      </column>
      <column name="email" type="text" nullable="false"></column>
      <column name="name" type="text"></column>
      <column name="deleted_at" type="timestamptz"></column>
      <pk name="pk_users">
        <column name="id"></column>
      </pk>
    </table>
    <table name="orders">
      <column name="id" type="bigint" nullable="false">
        <identity generated="always"></identity>
      </column>
      <column name="user_id" type="bigint" nullable="false"></column>
      <pk name="pk_orders">
        <column name="id"></column>
      </pk>
      <fk name="fk_orders_user" to-table="users" on-delete="cascade" on-update="no action">
        <column name="user_id" references="id"></column>
      </fk>
    </table>
  </schema>
</pgd>
XML
