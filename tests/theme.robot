*** Settings ***
Library    SSHLibrary

*** Variables ***
${module_id}    ${EMPTY}
${URL}          https://127.0.0.1/cluster-admin
${ADMIN_USER}    admin
${ADMIN_PASSWORD}    Nethesis,1234
${SHOTS}        ${OUTPUT DIR}/browser/screenshot
${DARK_BG}      rgb(22, 22, 22)

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

Open cluster-admin
    [Documentation]    New browser context with the OS color scheme set, logged in.
    [Arguments]    ${scheme}
    New Context    ignoreHTTPSErrors=True    colorScheme=${scheme}    viewport={'width': 1440, 'height': 900}
    New Page    https://${NODE_ADDR}/cluster-admin/
    Fill Text    text="Username"    ${ADMIN_USER}
    Click    button >> text="Continue"
    Fill Text    text="Password"    ${ADMIN_PASSWORD}
    Click    button >> text="Log in"
    Wait For Elements State    css=#main-content    visible    timeout=20s

Shot
    [Documentation]    Open a cluster-admin page, wait for it, save a numbered screenshot.
    [Arguments]    ${path}    ${ready}    ${name}
    Go To    https://${NODE_ADDR}/cluster-admin/#/${path}
    Wait For Elements State    ${ready}    visible    timeout=20s
    Sleep    3s
    Take Screenshot    filename=${SHOTS}/${name}.png

Body background should be
    [Arguments]    ${selector}    ${expected}
    ${bg} =    Evaluate JavaScript    ${selector}    (el) => getComputedStyle(el).backgroundColor
    Should Be Equal    ${bg}    ${expected}

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

Dark theme in the browser
    [Documentation]    Default "system" theme with the OS in dark mode: shell and
    ...    app pages are dark, the header button is present.
    [Tags]    ui
    Import Library    Browser
    New Browser    chromium    headless=True
    Open cluster-admin    dark
    Get Attribute    html    data-ns8-theme    ==    system
    Wait For Elements State    id=ns8-theme-toggle    visible    timeout=10s
    Body background should be    body    ${DARK_BG}
    Shot    status    text="Cluster status"    1._Dark_-_cluster_status
    Shot    software-center    text="Software center"    2._Dark_-_software_center
    Shot    nodes    text="Nodes"    3._Dark_-_nodes
    Shot    settings    text="Settings"    4._Dark_-_settings
    Shot    apps/${module_id}?page=status    iframe >>> h2 >> text="Status"    5._Dark_-_app_status
    Body background should be    iframe >>> body    ${DARK_BG}
    Shot    apps/${module_id}?page=settings    iframe >>> h2 >> text="Settings"    6._Dark_-_app_settings
    Close Context

Light theme in the browser
    [Documentation]    Same pages with the OS in light mode: stock look.
    [Tags]    ui
    Open cluster-admin    light
    Get Attribute    html    data-ns8-theme    ==    system
    ${bg} =    Evaluate JavaScript    body    (el) => getComputedStyle(el).backgroundColor
    Should Not Be Equal    ${bg}    ${DARK_BG}
    Shot    status    text="Cluster status"    7._Light_-_cluster_status
    Shot    apps/${module_id}?page=settings    iframe >>> h2 >> text="Settings"    8._Light_-_app_settings
    Close Context

Header button switches the theme
    [Documentation]    From System, the button goes to Light, then Dark; the choice
    ...    is a cookie that survives a reload and reaches the app iframe.
    [Tags]    ui
    Open cluster-admin    light
    Click    id=ns8-theme-toggle
    Get Attribute    html    data-ns8-theme    ==    light
    Click    id=ns8-theme-toggle
    Get Attribute    html    data-ns8-theme    ==    dark
    ${cookie} =    Get Cookie    ns8_theme
    Should Be Equal    ${cookie.value}    dark
    Go To    https://${NODE_ADDR}/cluster-admin/#/apps/${module_id}?page=status
    Reload
    Wait For Elements State    iframe >>> h2 >> text="Status"    visible    timeout=20s
    Get Attribute    html    data-ns8-theme    ==    dark
    Body background should be    iframe >>> body    ${DARK_BG}
    Sleep    3s
    Take Screenshot    filename=${SHOTS}/9._Dark_by_button_with_OS_in_light_mode.png
    Close Browser

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
