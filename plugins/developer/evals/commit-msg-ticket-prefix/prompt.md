---
description: >
  /commit-msg: префикс задачи из имени ветки, subject до 50 символов в повелительном наклонении,
  учитываются staged и unstaged изменения; без Makefile шаг fmt/lint пропускается и не мешает
  выдать сообщение. Diff передан в промпте, чтобы кейс не зависел от git внутри песочницы.
tags: [workflow]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

Сгенерируй commit message. Я на ветке PLF-852, вот что показывает git:

```
$ git diff --cached
diff --git a/pkg/vt/order.go b/pkg/vt/order.go
--- a/pkg/vt/order.go
+++ b/pkg/vt/order.go
@@ -1,6 +1,9 @@
 package vt

-import "errors"
+import (
+	"errors"
+	"net/mail"
+)

 type Order struct {
 	Email string
@@ -11,5 +14,11 @@ func (o Order) Validate() error {
 	if o.Email == "" {
 		return errors.New("email is required")
 	}
+	if _, err := mail.ParseAddress(o.Email); err != nil {
+		return errors.New("invalid email")
+	}
+	if l := len(o.Phone); l > 0 && (l < 10 || l > 15) {
+		return errors.New("phone must be 10-15 digits")
+	}
 	return nil
 }

$ git diff
diff --git a/pkg/vt/search.go b/pkg/vt/search.go
--- a/pkg/vt/search.go
+++ b/pkg/vt/search.go
@@ -1,5 +1,9 @@
 package vt

+import "time"
+
 type OrderSearch struct {
-	UserID *int
+	UserID        *int
+	CreatedAtFrom *time.Time
+	CreatedAtTo   *time.Time
 }

$ git status --short
M  pkg/vt/order.go
 M pkg/vt/search.go
```
