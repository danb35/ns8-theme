# get-configuration output Schema

```txt
http://schema.nethserver.org/theme/get-configuration-output.json
```

Get the cluster-admin theme configuration

| Abstract            | Extensible | Status         | Identifiable | Custom Properties | Additional Properties | Access Restrictions | Defined In                                                                                  |
| :------------------ | :--------- | :------------- | :----------- | :---------------- | :-------------------- | :------------------ | :------------------------------------------------------------------------------------------ |
| Can be instantiated | No         | Unknown status | No           | Forbidden         | Allowed               | none                | [get-configuration-output.json](theme/get-configuration-output.json "open original schema") |

## get-configuration output Type

`object` ([get-configuration output](get-configuration-output.md))

## get-configuration output Examples

```json
{
  "default_theme": "system",
  "show_toggle": true,
  "service_active": true
}
```

# get-configuration output Properties

| Property                          | Type      | Required | Nullable       | Defined by                                                                                                                                                                      |
| :-------------------------------- | :-------- | :------- | :------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [default_theme](#default_theme)   | `string`  | Required | cannot be null | [get-configuration output](get-configuration-output-properties-default_theme.md "http://schema.nethserver.org/theme/get-configuration-output.json#/properties/default_theme")   |
| [show_toggle](#show_toggle)       | `boolean` | Required | cannot be null | [get-configuration output](get-configuration-output-properties-show_toggle.md "http://schema.nethserver.org/theme/get-configuration-output.json#/properties/show_toggle")       |
| [service_active](#service_active) | `boolean` | Required | cannot be null | [get-configuration output](get-configuration-output-properties-service_active.md "http://schema.nethserver.org/theme/get-configuration-output.json#/properties/service_active") |

## default_theme



`default_theme`

* is required

* Type: `string`

* cannot be null

* defined in: [get-configuration output](get-configuration-output-properties-default_theme.md "http://schema.nethserver.org/theme/get-configuration-output.json#/properties/default_theme")

### default_theme Type

`string`

### default_theme Constraints

**enum**: the value of this property must be equal to one of the following values:

| Value      | Explanation |    |    |
| :--------- | :---------- | :- | :- |
| `"system"` |             |
| `"light"`  |             |
| `"dark"`   |             |

## show_toggle



`show_toggle`

* is required

* Type: `boolean`

* cannot be null

* defined in: [get-configuration output](get-configuration-output-properties-show_toggle.md "http://schema.nethserver.org/theme/get-configuration-output.json#/properties/show_toggle")

### show_toggle Type

`boolean`

## service_active

Whether the theme service (and so its routes) is running

`service_active`

* is required

* Type: `boolean`

* cannot be null

* defined in: [get-configuration output](get-configuration-output-properties-service_active.md "http://schema.nethserver.org/theme/get-configuration-output.json#/properties/service_active")

### service_active Type

`boolean`
