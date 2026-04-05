---
name: colgen
description: "Colgen — генератор коллекций для Go-структур. Используй при работе с collection.go и конвертерами между слоями."
---

# Colgen

`colgen` (https://github.com/vmkteam/colgen) - утилита для генерации различного кода и не только:
1. Стабильная (повторяемая) генерация кода
2. Генерация сниппетов (в инлайн режиме)
3. Работа с LLM (анализ кода)

Документация: https://vmkteam.dev/colgen/

## Генерация кода

Рассмотрим более подробно на примере проекта `newsportal`. Сколько раз в проектах мы встречали код вот такого типа?
```go
ids := make([]int, len(list))
for i := range list {
	ids = append(ids, i.ID)
}
```
То есть у нас есть какой-то `list`, например `[]News`, и нам нужно собрать все `ID` в слайс для дальнейшего использования.
Такие простые куски кода разрастаются по проекту, но не несут никакой смысловой нагрузки. Или рассмотрим другой пример – преобразование слайса в мап по ID:
```go
r := make(map[int]News, len(list))
for i, n := range list {
	r[n.ID] = n
}
```
И такого простого кода обычно много. Его можно упростить. Например, мы можем ввести понятие **коллекций**.

### Базовые генераторы
Создадим файл `collection.go`, в нем объявим новый тип и пару методов у него.
```go
type NewsList []News

func (ll NewsList) IDs() []int {
    r := make([]int, len(ll))
    for i := range ll {
        r[i] = ll[i].ID
    }
    return r
}

func (ll NewsList) Index() map[int]News {
    r := make(map[int]News, len(ll))
    for i := range ll {
        r[ll[i].ID] = ll[i]
    }
    return r
}
```
Теперь мы можем упросить основной код и использовать новые методы:
```go
nn := NewsList(list)
ids := nn.IDs()
idx := nn.Index()
```
**Плюсы:**
1. Утилитарный код ушел из бизнес-логики и был стандартизирован.
2. Появился новый тип, для которого мы можем добавить больше методов.
3. _Неочевидный плюс:_ стандартизируем нейминг, не нужно больше придумывать имена переменным в утилитарном коде.

**Минусы:**
1. Код все еще нужно писать.

Давайте попробуем убрать минусы и добавим в наш файл:
```go
//go:generate colgen
//colgen:News
```
Данная конструкция создаст новый файл с суффиксом `_colgen.go`, в котором будет базовый тип для структуры и два метода: `IDs()` и `Index()` (если есть поле ID).

### Дополнительные генераторы

Если поле `ID` отсутствует (например, вместо него `NewsID`), то можно добавить следующую конструкцию для аналогичного поведения:
```go
//go:generate colgen
//colgen:News
//colgen:News:NewsID,Index(NewsID)
```
В результате мы получим базовый тип и два метода: `NewsIDs()` и `IndexByNewsID()`.
Допустим, у новости есть теги `TagIDs`, и нам из списка надо получить уникальные теги. А у тегов есть поле `alias`, и нам нужно сделать индекс по нему.
```go
type News struct {
	ID     int
	Text   string
	TagIDs []int
}

type Tag struct {
	ID    int
	Alias string
}

//go:generate colgen
//colgen:News,Tag
//colgen:News:UniqueTagIDs
//colgen:Tag:Index(Alias)
```

Единственное, на что надо обращать внимание: код перед вызовом генератора **должен компилироваться**, потому что идет парсинг go файлов через AST.

#### Group(Field)
Можно сгруппировать слайс по определенному полю. `//colgen:News:Group(CategoryID)`:
```go
func (ll NewsList) GroupByCategoryID() map[int]NewsList {
    r := make(map[int]NewsList, len(ll))
    for i := range ll {
        r[ll[i].CategoryID] = append(r[ll[i].CategoryID], ll[i])
    }
    return r
}
```

### Новое в v0.1.3

Допустим, наша структура `News` стала сложнее — появились связи с авторами и статусами:
```go
type News struct {
	ID       int
	Text     string
	StatusID int
	TagIDs   []int
	Tags     []Tag
	AuthorID *int
	Author   *Author
}
```

#### `<Field>` для указателей и слайсов

Для скалярного поля `StatusID` всё как раньше — `//colgen:News:StatusID`:
```go
func (ll NewsList) StatusIDs() []int {
	r := make([]int, len(ll))
	for i := range ll {
		r[i] = ll[i].StatusID
	}
	return r
}
```
А вот для слайса `TagIDs []int` вместо `[][]int` мы получим плоский `[]int` — flatten. `//colgen:News:TagIDs`:
```go
func (ll NewsList) TagIDs() []int {
	var r []int
	for i := range ll {
		r = append(r, ll[i].TagIDs...)
	}
	return r
}
```
Для указателя `Author *Author` генератор добавит nil-check и разыменование. `//colgen:News:Author`:
```go
func (ll NewsList) Authors() []Author {
	var r []Author
	for i := range ll {
		if ll[i].Author != nil {
			r = append(r, *ll[i].Author)
		}
	}
	return r
}
```
Аналогично `Unique<Field>` теперь поддерживает `*T` поля: `//colgen:News:UniqueAuthorID` сгенерирует `UniqueAuthorIDs() []int` с nil-check и дедупликацией.

#### Count(Field)
`//colgen:News:Count(StatusID)`:
```go
func (ll NewsList) CountByStatusID(v int) int {
	var c int
	for i := range ll {
		if ll[i].StatusID == v {
			c++
		}
	}
	return c
}
```

#### Fill(Target,Junction)
Заполнение связей. Режим определяется автоматически по типу junction.

Для `[]int` junction (many-to-many). `//colgen:News:Fill(Tags,TagIDs)`:
```go
func (ll NewsList) FillTags(related Tags) NewsList {
	index := related.Index()
	for i := range ll {
		for _, id := range ll[i].TagIDs {
			if v, ok := index[id]; ok {
				ll[i].Tags = append(ll[i].Tags, v)
			}
		}
	}
	return ll
}
```
Для `*int` FK (one-to-one). `//colgen:News:Fill(Author,AuthorID)`:
```go
func (ll NewsList) FillAuthor(related Authors) NewsList {
	index := related.Index()
	for i := range ll {
		if ll[i].AuthorID != nil {
			if v, ok := index[*ll[i].AuthorID]; ok {
				ll[i].Author = &v
			}
		}
	}
	return ll
}
```
Использование:
```go
news = news.FillTags(tags).FillAuthor(authors)
```
Методы возвращают тот же список, поэтому их удобно чейнить.

#### Cast(Interface)
Если структура реализует интерфейс через pointer receiver. `//colgen:News:Cast(Searchable)`:
```go
func (ll NewsList) Searchables() []Searchable {
	r := make([]Searchable, len(ll))
	for i := range ll {
		r[i] = &ll[i]
	}
	return r
}
```

#### Group по слайсу (fan-out)
Один элемент попадёт в несколько групп. `//colgen:News:Group(TagIDs)`:
```go
func (ll NewsList) GroupByTagIDs() map[int]NewsList {
	r := make(map[int]NewsList)
	for i := range ll {
		for _, v := range ll[i].TagIDs {
			r[v] = append(r[v], ll[i])
		}
	}
	return r
}
```

### Map & MapP

```go
//go:generate colgen -imports=newsportal/pkg/db
//colgen:News,Tag
//colgen:News:UniqueTagIDs,Map(db)
//colgen:Tag:Index(Alias)
```
Добавление `Map(db)` сгенерирует:
```go
func NewNewsList(in []db.News) NewsList { return Map(in, NewNews) }
```
* Если `NewNews` принимает `*db.News`, то необходимо использовать `MapP(db)`.
* Если нужны приватные конструкторы, то используем `mapp/map` вместо `MapP/Map`
* Если название структуры в `db` слое отличается, то используем полный путь: `Map(db.News)`
* Если структура не описана в базовой генерации `//colgen:News,Tags,...`, то конструктор будет возвращать `[]News` вместо `NewsList`
* Для стабильной генерации добавляем импорт в файл через флаг: `-imports=newsportal/pkg/db`
* Если `Map/MapP` лежат в другом пакете, то нужно добавить этот пакет в импорт через запятую и добавить название пакета через `-funcpkg=<pkg>`.
* Не забудем добавить в проект те самые два дженерика:
```go
// MapP converts slice of type T to slice of type M with given converter with pointers.
func MapP[T, M any](a []T, f func(*T) *M) []M {
	n := make([]M, len(a))
	for i := range a {
		n[i] = *f(&a[i])
	}
	return n
}

// Map converts slice of type T to slice of type M with given converter.
func Map[T, M any](a []T, f func(T) M) []M {
	n := make([]M, len(a))
	for i := range a {
		n[i] = f(a[i])
	}
	return n
}
```
Рекомендуется иметь один `colgen` на пакет. Директивы `//go:generate colgen` можно размещать в файле `collection.go`.

>Если все сломалось, то удаляйте файл `_colgen.go` и вызывайте генератор снова. Но! Если функции генератора уже используются в коде, то при удалении файла будет нерабочий код и генератор не запустится.

Шаги для максимальной генерации:
1. Делаем базовые типы и методы.
2. Создаем сниппеты конструктора через инлайн режим.
3. Добавляем себе в проект `Map/MapP` дженерики.
4. В последнюю очередь добавляем `Map/MapP` генераторы. Если их добавить в пункте 1, то будет некомпилируемый код из-за отсутствия функций конструктора.

## Генерация сниппетов в инлайн режиме

```go
//go:generate colgen
...
//colgen@NewNews(db)
```

При генерации директива `//colgen@NewNews(db)` **будет заменена в этом файле** на следующий код:
```go
type News struct {
    db.News
}

func NewNews(in *db.News) *News {
    if in == nil {
        return nil
    }
    return &News{
        News: *in,
    }
}
```

Второй пример `//colgen@newNewsSummary(db.News,full,json)`:
```go
type NewsSummary struct {
    ID     int    `json:"newsSummaryId"`
    Text   string `json:"text"`
    TagIDs []int  `json:"tagIDs"`
}

func newNewsSummary(in *db.News) *NewsSummary {
    if in == nil {
        return nil
    }
    return &NewsSummary{
        ID:     in.ID,
        Text:   in.Text,
        TagIDs: in.TagIDs,
    }
}
```

Когда мы говорим о доменном слое, то нам подходит первый вариант (embed).
Когда мы говорим о слое с апи, нам подходит второй вариант (full, json).

На сложных объектах вы будете получать невалидный сниппет. Но базовая идея заключается в том, чтобы получить сниппет, а потом его отредактировать как нужно.

## Работа с LLM

Для работы с `DeepSeek` или `Claude` у вас должен быть API ключ. Работа с LLM идет в рамках файла, именно его содержимое (+тест, если применимо) + промт отправляется на сервер.

Три режима:
* `//colgen@ai:review` – код ревью с идиоматичным промтом. Результат в файле с суффиксом `.md`.
* `//colgen@ai:readme` – генерация README.md по текущему файлу.
* `//colgen@ai:tests` – генерация тестов с нуля или дописывание `_test.go`.

Для выбора LLM в конце добавить `(deepseek)` или `(claude)`. DeepSeek по умолчанию.
```
//go:generate colgen
//colgen@ai:readme           // makes readme using deepseek by default
//colgen@ai:tests(deepseek)  // makes tests using deepseek explicitly
//colgen@ai:review(claude)   // makes review using claude
```

## Маркеры

- Сгенерированные файлы: `*_colgen.go` с заголовком `// Code generated by colgen; DO NOT EDIT.`
- Безопасно редактировать: `collection.go` (аннотации), файлы с конвертерами
