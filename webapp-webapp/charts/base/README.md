# base

## Description

Базовый чарт. Возможно развертывание в двух вариантах workload'ов:

- Deployment
- StatefulSet

## Миграция с basestateless

Для перехода с basestateless необходимо добавить в корень values поле type:

```yaml
type: stateless
```

## TODO

- [ ] Inject basejob here.
- [x] Add startupProbe to workload.
