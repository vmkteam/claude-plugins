---
type: llm
---

PASS if the rewrite replaces the hand-written loops with colgen-generated collection methods declared by //colgen: directives in the domain package's collection.go: unique product ids (e.g. UniqueProductIDs), and either an index by id (Index / IndexBy…) or a Fill… method for the Product relation (Fill builds the index itself, so a separate Index is not required), plus list conversion via MapP/Map constructors (e.g. NewOrderList / NewOrders).
FAIL if the answer keeps hand-written loops for these steps, introduces its own generic helpers instead of colgen collection methods (the Map/MapP generics that colgen requires in the package are fine), or puts the collections into pkg/db.
