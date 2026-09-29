#!/usr/bin/env bash
# Схема в формате MicroOLAP Database Designer (.pdd) — должен сработать /pgmdd, а не /pgd.
set -euo pipefail
mkdir -p docs
cat > docs/shop.pdd <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<DBMODEL Version="1.92" TYPE="PostgreSQL">
<MODELSETTINGS MDDVERSION="1.12.4" ModelProject="" ModelName="shop" ModelCompany="" ModelAuthor="" ModelCopyright="" ModelVersion="" ModelVersionAI="0" ModelCreated="2025-01-10 12:00:00" ModelUpdated="2025-01-10 12:00:00" Description="" Annotation="" ZoomFac="100.00" XPos="0" YPos="0" PrintLink="" GenSettings="object GenSettings1\n  ObjectName = 'GenSettings1'\nend" DisplaySettings=""/>
<DATABASE Name="shop" CharacterSet="UTF8" Collate="" CType="" Tablespace="" Owner="" Template="" Comments="" Description="" Annotation="" BeginScript="" EndScript="" Generate="1"/>
<SCHEMAS>
<SCHEMA ID="10" Name="public" Owner="" Comments="" Description="" Annotation="" BeginScript="" EndScript="" Generate="1" System="1"/>
</SCHEMAS>
<COMPOSITES>
<COMPOSITE ID="200" Name="users" SchemaName="public" OwnerName="" Comments="" MasterTableOID="100">
<COLUMNS>
</COLUMNS>
</COMPOSITE>
</COMPOSITES>
<METADATA>
<ENTITIES>
<ENTITY ID="100" Name="users" SchemaOID="10" SchemaName="public" OwnerID="0" OwnerName="" TablespaceID="0" XPos="100" YPos="100" Temporary="0" Unlogged="0" OnCommit="" Inherits="" FillFactor="0" Comments="" Description="" Annotation="" BeginScript="" EndScript="" Generate="1" ACL="" StorageParams="" SysColumns="" SysColumnsVisible="0">
<COLUMNS>
<COLUMN ID="101" Name="userId" Pos="0" Datatype="23" Type="int4" Width="0" Prec="0" NotNull="1" AutoInc="2" PrimaryKey="1" IsFKey="0" DefaultValue="" QuoteDefault="0" Comments=""/>
<COLUMN ID="102" Name="email" Pos="1" Datatype="25" Type="text" Width="0" Prec="0" NotNull="1" AutoInc="0" PrimaryKey="0" IsFKey="0" DefaultValue="" QuoteDefault="0" Comments=""/>
<COLUMN ID="103" Name="createdAt" Pos="2" Datatype="1184" Type="timestamp with time zone" Width="-1" Prec="0" NotNull="1" AutoInc="0" PrimaryKey="0" IsFKey="0" DefaultValue="now()" QuoteDefault="0" Comments=""/>
</COLUMNS>
<CONSTRAINTS>
<CONSTRAINT ID="104" Name="users_pkey" Kind="2" Expression="" ReferenceIndex="0" FillFactor="0" Comments="" TablespaceID="0" Deferrable="0" Method="0">
<CONSTRAINTCOLUMNS COMMATEXT="userId"/>
</CONSTRAINT>
</CONSTRAINTS>
<INDEXES>
</INDEXES>
</ENTITY>
</ENTITIES>
<REFERENCES>
</REFERENCES>
</METADATA>
</DBMODEL>
XML
