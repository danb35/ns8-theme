*** Settings ***
Library    SSHLibrary

*** Variables ***
${module_id}    ${EMPTY}
${URL}          https://127.0.0.1/cluster-admin

*** Keywords ***
Get core.css size with cookie
    [Arguments]    ${theme}
    ${size} =    Execute Command    curl -sk -o /dev/null -w '\%{size_download}' -b ns8_theme=${theme} ${URL}/css/core.css
    RETURN    ${size}

Routes count
    ${n} =    Execute Command    ls /home/traefik*/.config/state/configs/ | grep -c '^${module_id}-'
    RETURN    ${n}

Routes count should be
    [Arguments]    ${expected}
    ${n} =    Routes count
    Should Be Equal As Integers    ${n}    ${expected}

*** Test Cases ***
Record the stock core.css size
    ${stock} =    Execute Command    curl -sk -o /dev/null -w '\%{size_download}' ${URL}/css/core.css
    Set Global Variable    ${stock_size}    ${stock}

Install the module
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Global Variable    ${module_id}    ${output.module_id}

The service starts and adds both routes
    Wait Until Keyword Succeeds    60s    3s    Routes count should be    2
    ${rc} =    Execute Command    runagent -m ${module_id} systemctl --user is-active theme.service
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}  0

config.production.js still defines CONFIG and carries the loader
    ${js} =    Execute Command    curl -sk ${URL}/config/config.production.js
    Should Contain    ${js}    window.CONFIG
    Should Contain    ${js}    NS8_THEME_CONF
    Should Contain    ${js}    "default": "system"

core.css variants follow the cookie
    ${light} =    Get core.css size with cookie    light
    Should Be Equal    ${light}    ${stock_size}
    ${dark} =    Get core.css size with cookie    dark
    Should Be True    ${dark} > ${stock_size}
    ${system} =    Execute Command    curl -sk ${URL}/css/core.css | tail -c 200000 | grep -c 'prefers-color-scheme: dark'
    Should Be True    ${system} >= 1

Configure the default theme
    ${out}  ${rc} =    Execute Command    api-cli run module/${module_id}/configure-module --data '{"default_theme": "dark", "show_toggle": false}'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    Wait Until Keyword Succeeds    60s    3s    Routes count should be    2
    ${js} =    Execute Command    curl -sk ${URL}/config/config.production.js
    Should Contain    ${js}    "default": "dark"
    Should Contain    ${js}    "toggle": false
    ${cfg} =    Execute Command    api-cli run module/${module_id}/get-configuration
    Should Contain    ${cfg}    "default_theme": "dark"

Stopping the service restores the stock files
    Execute Command    runagent -m ${module_id} systemctl --user stop theme.service
    Wait Until Keyword Succeeds    60s    3s    Routes count should be    0
    ${size} =    Get core.css size with cookie    dark
    Should Be Equal    ${size}    ${stock_size}
    Execute Command    runagent -m ${module_id} systemctl --user start theme.service
    Wait Until Keyword Succeeds    60s    3s    Routes count should be    2

Remove the module
    ${rc} =    Execute Command    remove-module --no-preserve ${module_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    Wait Until Keyword Succeeds    60s    3s    Routes count should be    0
    ${size} =    Get core.css size with cookie    dark
    Should Be Equal    ${size}    ${stock_size}
