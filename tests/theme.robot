*** Settings ***
Library    SSHLibrary
Library    String

*** Variables ***
${module_id}    ${EMPTY}
${URL}          https://127.0.0.1/cluster-admin
${ADMIN_USER}    admin
${ADMIN_PASSWORD}    Nethesis,1234
${SHOTS}        ${OUTPUT DIR}/browser/screenshot
${DARK_BG}      rgb(22, 22, 22)
# Highest share of dark.css class names allowed to be missing from the live
# core.css before we call the theme stale (about 6% with core 3.25.1, mostly
# ns8-ui-lib classes that ship inside each app instead).
${MAX_MISSING_PCT}    15

*** Keywords ***
Get core.css size with cookie
    [Arguments]    ${theme}
    ${size} =    Execute Command    curl -sk -o /dev/null -w '\%{size_download}' -b ns8_theme=${theme} ${URL}/css/core.css
    RETURN    ${size}

Routes count
    ${files} =    Execute Command    ls /home/traefik*/.config/state/configs/ | grep -E '^${module_id}-(cfg|css)\\.yml$' || true
    Log    route files: ${files}
    @{lines} =    Split To Lines    ${files}
    ${n} =    Get Length    ${lines}
    RETURN    ${n}

Routes count should be
    [Arguments]    ${expected}
    ${n} =    Routes count
    Should Be Equal As Integers    ${n}    ${expected}

Service should be active
    ${rc} =    Execute Command    runagent -m ${module_id} systemctl --user is-active theme.service
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

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

Core still loads config.production.js by that name
    [Documentation]    The loader rides on this unhashed script (DESIGN.md 3.3).
    ${n} =    Execute Command    curl -sk ${URL}/ | grep -c 'src="config/config.production.js"'
    Should Be True    ${n} >= 1    index.html no longer loads config/config.production.js

Core's cluster-admin route is below our priority
    [Documentation]    Our routes win only while core's stay below 100100.
    ${p} =    Execute Command    grep -h 'priority:' /home/traefik*/.config/state/configs/cluster-admin.yml | awk '{print $2}' | sort -n | tail -1
    Should Be True    0 < ${p} < 100100    core's cluster-admin route priority is ${p}

Install the module
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Global Variable    ${module_id}    ${output.module_id}

The service starts and adds both routes
    Wait Until Keyword Succeeds    60s    3s    Routes count should be    2
    Wait Until Keyword Succeeds    30s    2s    Service should be active

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

Responses are compressed, uncached and vary by cookie
    ${h} =    Execute Command    curl -sk -D - -o /dev/null -H 'Accept-Encoding: gzip' -b ns8_theme=dark ${URL}/css/core.css
    Should Match Regexp    ${h}    (?i)content-encoding: gzip
    Should Match Regexp    ${h}    (?i)cache-control: no-cache
    Should Match Regexp    ${h}    (?i)vary: [^\n]*cookie
    ${h} =    Execute Command    curl -sk -D - -o /dev/null ${URL}/config/config.production.js
    Should Match Regexp    ${h}    (?i)cache-control: no-cache
    ${r} =    Execute Command    curl -s -o /dev/null -w '\%{http_code} \%{redirect_url}' http://127.0.0.1/cluster-admin/config/config.production.js
    Should Match Regexp    ${r}    ^30[18] https://

The dark stylesheet still matches the core UI
    [Documentation]    Warns when a core UI release renames the classes the
    ...    generated theme targets (dark.css is built from a fixed core release).
    Put File    ${CURDIR}/scripts/class-coverage.sh    /tmp/class-coverage.sh    mode=0755
    ${out} =    Execute Command    /tmp/class-coverage.sh ${module_id}
    Execute Command    rm -f /tmp/class-coverage.sh
    @{lines} =    Split To Lines    ${out}
    @{counts} =    Split String    ${lines}[0]
    ${missing} =    Convert To Integer    ${counts}[0]
    ${total} =    Convert To Integer    ${counts}[1]
    ${pct} =    Evaluate    round(100 * ${missing} / ${total}, 1)
    Log    ${missing} of ${total} class names (${pct}%) are not in the live core.css: ${lines}[1:]    console=True
    Should Be True    ${total} > 100    dark.css looks empty
    Should Be True    ${pct} < ${MAX_MISSING_PCT}    ${pct}% of dark.css class names no longer exist in core.css: rebuild against the current core

Every app UI links the shared core.css
    [Documentation]    The theme reaches app pages only through this link. Only
    ...    real module UIs (id="ns8-app") count: some core modules ship a
    ...    placeholder or redirect page instead.
    ${out} =    Execute Command    for f in /var/lib/nethserver/cluster/ui/apps/*/index.html; do grep -q 'id="ns8-app"' "$f" || continue; grep -q '/cluster-admin/css/core.css' "$f" || echo "$f"; done
    Should Be Empty    ${out}    these app UIs do not link /cluster-admin/css/core.css: ${out}

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
    Shot    status    h2 >> text="Cluster status"    1._Dark_-_cluster_status
    # Low-contrast notifications kept a light tinted background with light
    # text in 0.1.0; every kind must have a dark body (DESIGN.md 4.3).
    ${bgs} =    Evaluate JavaScript    ${None}
    ...    () => ['warning', 'error', 'success', 'info'].map((k) => {
    ...        const n = document.createElement('div');
    ...        n.className = 'bx--inline-notification bx--inline-notification--' + k + ' bx--inline-notification--low-contrast';
    ...        document.body.appendChild(n);
    ...        const bg = getComputedStyle(n).backgroundColor;
    ...        n.remove();
    ...        return bg;
    ...    })
    FOR    ${bg}    IN    @{bgs}
        Should Be Equal    ${bg}    rgb(38, 38, 38)    low-contrast notification background is ${bg}
    END
    Shot    software-center    h2 >> text="Software center"    2._Dark_-_software_center
    Shot    nodes    h2 >> text="Nodes"    3._Dark_-_nodes
    Shot    settings    h2 >> text="Settings"    4._Dark_-_settings
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
    Shot    status    h2 >> text="Cluster status"    7._Light_-_cluster_status
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

Invalid settings are rejected
    ${out}  ${rc} =    Execute Command    api-cli run module/${module_id}/configure-module --data '{"default_theme": "purple"}'
    ...    return_rc=True
    Should Not Be Equal As Integers    ${rc}    0
    ${cfg} =    Execute Command    api-cli run module/${module_id}/get-configuration
    Should Contain    ${cfg}    "default_theme": "system"

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

A second instance on the same node is refused
    [Documentation]    Two instances would fight over the routes. The image's
    ...    max-per-node label binds only the Software Center, so create-module
    ...    checks too. core leaves the refused instance registered: remove it.
    ${out}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    ${extra} =    Execute Command    redis-cli hkeys cluster/module_node | grep -E '^theme[0-9]+$' | grep -vx '${module_id}' || true
    @{extras} =    Split To Lines    ${extra}
    FOR    ${m}    IN    @{extras}
        Execute Command    remove-module --no-preserve ${m}
    END
    Should Not Be Equal As Integers    ${rc}    0    a second instance was installed on the same node
    Routes count should be    2

A crashed nginx is replaced and the routes come back
    [Documentation]    The routes must disappear while nginx is down (stock
    ...    cluster-admin), and return once systemd restarts it.
    Execute Command    runagent -m ${module_id} podman kill theme
    Wait Until Keyword Succeeds    30s    1s    Routes count should be    0
    Wait Until Keyword Succeeds    90s    3s    Routes count should be    2
    # The second route appears while ExecStartPost is still finishing.
    Wait Until Keyword Succeeds    30s    2s    Service should be active

Stopping the service restores the stock files
    Execute Command    runagent -m ${module_id} systemctl --user stop theme.service
    Wait Until Keyword Succeeds    60s    3s    Routes count should be    0
    ${size} =    Get core.css size with cookie    dark
    Should Be Equal    ${size}    ${stock_size}
    ${cfg} =    Execute Command    api-cli run module/${module_id}/get-configuration
    Should Contain    ${cfg}    "service_active": false
    Execute Command    runagent -m ${module_id} systemctl --user start theme.service
    Wait Until Keyword Succeeds    60s    3s    Routes count should be    2

Remove the module
    ${rc} =    Execute Command    remove-module --no-preserve ${module_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    Wait Until Keyword Succeeds    60s    3s    Routes count should be    0
    ${size} =    Get core.css size with cookie    dark
    Should Be Equal    ${size}    ${stock_size}
