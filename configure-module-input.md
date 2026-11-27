# configure-module input Schema

```txt
http://schema.nethserver.org/theme/configure-module-input.json
```

Configure the cluster-admin theme

| Abstract            | Extensible | Status         | Identifiable | Custom Properties | Additional Properties | Access Restrictions | Defined In                                                                              |
| :------------------ | :--------- | :------------- | :----------- | :---------------- | :-------------------- | :------------------ | :-------------------------------------------------------------------------------------- |
| Can be instantiated | No         | Unknown status | No           | Forbidden         | Forbidden             | none                | [configure-module-input.json](theme/configure-module-input.json "open original schema") |

## configure-module input Type

`object` ([configure-module input](configure-module-input.md))

## configure-module input Examples

```json
{
  "default_theme": "system",
  "show_toggle": true
}
```

# configure-module input Properties

| Property                        | Type      | Required | Nullable       | Defined by                                                                                                                                                              |
| :------------------------------ | :-------- | :------- | :------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [default_theme](#default_theme) | `string`  | Required | cannot be null | [configure-module input](configure-module-input-properties-default_theme.md "http://schema.nethserver.org/theme/configure-module-input.json#/properties/default_theme") |
| [show_toggle](#show_toggle)     | `boolean` | Optional | cannot be null | [configure-module input](configure-module-input-properties-show_toggle.md "http://schema.nethserver.org/theme/configure-module-input.json#/properties/show_toggle")     |

## default_theme

Theme for browsers that have not chosen one with the header button

`default_theme`

* is required

* Type: `string`

* cannot be null

* defined in: [configure-module input](configure-module-input-properties-default_theme.md "http://schema.nethserver.org/theme/configure-module-input.json#/properties/default_theme")

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

Show the theme button in the cluster-admin header

`show_toggle`

* is optional

* Type: `boolean`

* cannot be null

* defined in: [configure-module input](configure-module-input-properties-show_toggle.md "http://schema.nethserver.org/theme/configure-module-input.json#/properties/show_toggle")

### show_toggle Type

`boolean`
