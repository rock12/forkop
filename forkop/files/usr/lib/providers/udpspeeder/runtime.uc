#!/usr/bin/env ucode

let fs = require("fs");
let uci_core = require("core.uci");
let runtime_constants = require("singbox.constants");

const CONFIG_NAME = getenv("FORKOP_CONFIG_NAME") || "forkop";
const LIB_DIR = getenv("FORKOP_LIB") || "/usr/lib/forkop";
const UDPSPEEDER_BIN = getenv("UDPSPEEDER_BIN") || "/usr/bin/udpspeeder";
const UDPSPEEDER_SERVICE_INIT = getenv("UDPSPEEDER_SERVICE_INIT") || "/etc/init.d/udpspeeder";
const UDPSPEEDER_STATE_DIR = getenv("UDPSPEEDER_STATE_DIR") || "/var/run/forkop/udpspeeder";
const UDPSPEEDER_PID_DIR = getenv("UDPSPEEDER_PID_DIR") || UDPSPEEDER_STATE_DIR + "/pid";
const UDPSPEEDER_CHILD_PID_DIR = getenv("UDPSPEEDER_CHILD_PID_DIR") || UDPSPEEDER_STATE_DIR + "/child-pid";
const UDPSPEEDER_LOG_DIR = getenv("UDPSPEEDER_LOG_DIR") || UDPSPEEDER_STATE_DIR + "/log";
const UDPSPEEDER_LISTEN_ADDRESS = getenv("UDPSPEEDER_LISTEN_ADDRESS") || "127.0.0.1";
const UDPSPEEDER_PORT_BASE = getenv("UDPSPEEDER_PORT_BASE") || "6500";
const UDPSPEEDER_RESPAWN_DELAY = getenv("UDPSPEEDER_RESPAWN_DELAY") || "5";

function as_string(value) {
    return value == null ? "" : "" + value;
}

function bool_value(value) {
    value = lc(as_string(value));
    return value == "1" || value == "true" || value == "yes" || value == "on";
}

function write_json(value) {
    print(sprintf("%J", value), "\n");
}

function shell_quote(value) {
    return "'" + replace(as_string(value), /'/g, "'\\''") + "'";
}

function command_from_args(args) {
    let parts = [];
    for (let arg in args)
        push(parts, shell_quote(arg));
    return join(" ", parts);
}

function command_output(command) {
    let pipe = fs.popen(command, "r");
    if (!pipe)
        return "";

    let data = pipe.read("all");
    let status = pipe.close();
    if (status != 0 || data == null)
        return "";
    return as_string(data);
}

function command_output_from_args(args) {
    return command_output(command_from_args(args));
}

function command_status(command) {
    let status = int(system(command));
    return status > 255 ? int(status / 256) : status;
}

function command_success_from_args(args) {
    return system(command_from_args(args) + " >/dev/null 2>&1") == 0;
}

function log_message(message, level) {
    level = as_string(level || "info");
    command_success_from_args([ "logger", "-t", "forkop", "[" + level + "] " + as_string(message) ]);
}

function object_or_empty(value) {
    return type(value) == "object" ? value : {};
}

function option(section, key, fallback) {
    if (fallback == null)
        fallback = "";

    let value = object_or_empty(section)[key];
    if (value == null)
        return fallback;
    if (type(value) == "array")
        return join(" ", value);
    return as_string(value);
}

function bool_option(section, key, fallback) {
    let value = object_or_empty(section)[key];
    return value == null ? !!fallback : bool_value(value);
}

function section_name(section) {
    return as_string(object_or_empty(section)[".name"]);
}

function uci_sections(type_name) {
    return uci_core.section_objects(CONFIG_NAME, as_string(type_name));
}

function uci_settings() {
    return object_or_empty(uci_core.get_all(CONFIG_NAME, "settings"));
}

function enabled_udpspeeder_sections() {
    let result = [];
    for (let section in uci_sections("section"))
        if (bool_option(section, "enabled", true) && option(section, "action", "") == "udpspeeder")
            push(result, section);
    return result;
}

function enabled_rule_count() {
    return length(enabled_udpspeeder_sections());
}

function section_local_port(section, index_value) {
    let configured_port = int(option(section, "udpspeeder_local_port", ""));
    if (configured_port > 0 && configured_port <= 65535)
        return configured_port;
    return int(UDPSPEEDER_PORT_BASE) + int(index_value) - 1;
}

function ensure_runtime_dirs() {
    return command_success_from_args([ "mkdir", "-p", UDPSPEEDER_STATE_DIR, UDPSPEEDER_PID_DIR, UDPSPEEDER_CHILD_PID_DIR, UDPSPEEDER_LOG_DIR ]);
}

function provider_available() {
    let stat = fs.stat(UDPSPEEDER_BIN);
    return stat != null && stat.mode != null && (int(stat.mode) & 73) != 0;
}

function package_installed() {
    return provider_available() || command_success_from_args([ "ucode", "-L", LIB_DIR, LIB_DIR + "/core/packages.uc", "installed", "udpspeeder" ]);
}

function package_version() {
    if (provider_available()) {
        let out = command_output_from_args([ UDPSPEEDER_BIN, "-h" ]);
        let m = match(out, /git version: *([0-9.]+)/);
        if (m)
            return m[1];
    }
    return "";
}

function standalone_service_enabled() {
    return fs.stat(UDPSPEEDER_SERVICE_INIT) != null && command_success_from_args([ UDPSPEEDER_SERVICE_INIT, "enabled" ]);
}

function standalone_service_running() {
    return fs.stat(UDPSPEEDER_SERVICE_INIT) != null && command_success_from_args([ UDPSPEEDER_SERVICE_INIT, "status" ]);
}

function runtime_pid_running(pid) {
    pid = as_string(pid);
    return match(pid, /^[0-9]+$/) != null && command_success_from_args([ "kill", "-0", pid ]);
}

function file_first_line(path) {
    let data = fs.readfile(as_string(path));
    if (data == null)
        return "";
    let newline = index(data, "\n");
    return trim(newline >= 0 ? substr(data, 0, newline) : data);
}

function kill_pidfile_process(path, signal) {
    let pid = file_first_line(path);
    if (pid == "")
        return;
    if (signal == "9") {
        if (runtime_pid_running(pid))
            command_success_from_args([ "kill", "-9", pid ]);
    }
    else {
        command_success_from_args([ "kill", pid ]);
    }
}

function pidfiles_in_dir(path) {
    if (fs.stat(path) == null)
        return [];

    let output = command_output_from_args([ "find", path, "-maxdepth", "1", "-type", "f", "-name", "*.pid" ]);
    let result = [];
    for (let line in split(output, "\n")) {
        line = trim(as_string(line));
        if (line != "")
            push(result, line);
    }
    return result;
}

function stop_runtime() {
    for (let pidfile in pidfiles_in_dir(UDPSPEEDER_PID_DIR))
        kill_pidfile_process(pidfile, "");
    for (let pidfile in pidfiles_in_dir(UDPSPEEDER_CHILD_PID_DIR))
        kill_pidfile_process(pidfile, "");

    command_success_from_args([ "sleep", "1" ]);

    for (let pidfile in pidfiles_in_dir(UDPSPEEDER_PID_DIR))
        kill_pidfile_process(pidfile, "9");
    for (let pidfile in pidfiles_in_dir(UDPSPEEDER_CHILD_PID_DIR))
        kill_pidfile_process(pidfile, "9");

    command_success_from_args([ "rm", "-rf", UDPSPEEDER_PID_DIR, UDPSPEEDER_CHILD_PID_DIR, UDPSPEEDER_LOG_DIR ]);
}

function strategy_words(value) {
    value = replace(as_string(value), /[\t\r\n]/g, " ");
    value = replace(value, / +/g, " ");
    value = replace(value, /^ /, "");
    value = replace(value, / $/, "");
    return value == "" ? [] : split(value, " ");
}

function supervisor_command(local_port, server_host, server_port, key, mode, fec, mtu, extra_opts, child_pidfile) {
    let args = [
        UDPSPEEDER_BIN,
        "-c",
        "-l", UDPSPEEDER_LISTEN_ADDRESS + ":" + local_port,
        "-r", server_host + ":" + server_port
    ];

    if (key != "") {
        push(args, "-k");
        push(args, key);
    }

    if (mode != "") {
        push(args, "--mode");
        push(args, mode);
    }

    if (fec != "") {
        push(args, "-f");
        push(args, fec);
    }

    if (mtu != "") {
        push(args, "--mtu");
        push(args, mtu);
    }

    for (let word in strategy_words(extra_opts))
        push(args, word);

    return command_from_args(args) + " & child=$!; echo $child > " + shell_quote(child_pidfile) + "; wait $child; rc=$?; rm -f " + shell_quote(child_pidfile) + "; exit $rc";
}

function supervisor(section, local_port, server_host, server_port, key, mode, fec, mtu, extra_opts, child_pidfile) {
    while (true) {
        if (!provider_available()) {
            print(command_output_from_args([ "date", "+%Y-%m-%d %H:%M:%S" ]), " Provider ", UDPSPEEDER_BIN, " is not executable; retrying in ", UDPSPEEDER_RESPAWN_DELAY, " seconds\n");
            command_success_from_args([ "sleep", UDPSPEEDER_RESPAWN_DELAY ]);
            continue;
        }

        let rc = command_status("sh -c " + shell_quote(supervisor_command(local_port, server_host, server_port, key, mode, fec, mtu, extra_opts, child_pidfile)));
        print(command_output_from_args([ "date", "+%Y-%m-%d %H:%M:%S" ]), " udpspeeder for rule ", as_string(section), " exited with code ", rc, "; respawning in ", UDPSPEEDER_RESPAWN_DELAY, " seconds\n");
        command_success_from_args([ "sleep", UDPSPEEDER_RESPAWN_DELAY ]);
    }
}

function start_rule(section, index_value) {
    let name = section_name(section);
    let local_port = "" + section_local_port(section, index_value);
    let server_host = option(section, "udpspeeder_server", "");
    let server_port = option(section, "udpspeeder_server_port", "");
    let key = option(section, "udpspeeder_key", "");
    let mode = option(section, "udpspeeder_mode", "0");
    let fec = option(section, "udpspeeder_fec", "20:10");
    let mtu = option(section, "udpspeeder_mtu", "1250");
    let extra_opts = option(section, "udpspeeder_extra_opts", "--fix-latency");

    if (server_host == "" || server_port == "") {
        log_message("UDPspeeder rule '" + name + "' missing server host or port. Skipped.", "warn");
        return;
    }

    let pidfile = UDPSPEEDER_PID_DIR + "/" + name + ".pid";
    let child_pidfile = UDPSPEEDER_CHILD_PID_DIR + "/" + name + ".pid";
    let logfile = UDPSPEEDER_LOG_DIR + "/" + name + ".log";

    log_message("Starting udpspeeder for rule '" + name + "' on " + UDPSPEEDER_LISTEN_ADDRESS + ":" + local_port + " -> " + server_host + ":" + server_port, "info");
    let command = command_from_args([
        "ucode",
        "-L", LIB_DIR,
        LIB_DIR + "/providers/udpspeeder/runtime.uc",
        "supervisor",
        name,
        local_port,
        server_host,
        server_port,
        key,
        mode,
        fec,
        mtu,
        extra_opts,
        child_pidfile
    ]) + " >>" + shell_quote(logfile) + " 2>&1 1000>&- & echo $!";
    let pid = trim(command_output("sh -c " + shell_quote(command)));
    if (pid == "" || !fs.writefile(pidfile, pid + "\n")) {
        log_message("udpspeeder failed to start for rule '" + name + "'. Check " + logfile + ". Aborted.", "fatal");
        exit(1);
    }

    command_success_from_args([ "sleep", "1" ]);
    if (!runtime_pid_running(pid)) {
        log_message("udpspeeder failed to start for rule '" + name + "'. Check " + logfile + ". Aborted.", "fatal");
        exit(1);
    }

    let child_pid = file_first_line(child_pidfile);
    if (child_pid == "" || !runtime_pid_running(child_pid))
        log_message("udpspeeder supervisor started for rule '" + name + "', but udpspeeder process is not running yet. Check " + logfile + ".", "warn");
}

function start_runtime() {
    stop_runtime();

    let sections = enabled_udpspeeder_sections();
    if (length(sections) == 0 || !provider_available())
        return;

    if (standalone_service_enabled())
        log_message("Standalone udpspeeder service is enabled. Forkop manages udpspeeder itself for action 'udpspeeder'.", "warn");

    if (!ensure_runtime_dirs()) {
        log_message("Failed to prepare the Forkop UDPspeeder state directory in " + UDPSPEEDER_STATE_DIR + ". Aborted.", "fatal");
        exit(1);
    }

    let index_value = 1;
    for (let section in sections) {
        start_rule(section, index_value);
        index_value++;
    }
}

function live_pid_count(path) {
    let count = 0;
    for (let pidfile in pidfiles_in_dir(path)) {
        let pid = file_first_line(pidfile);
        if (runtime_pid_running(pid))
            count++;
        else
            fs.unlink(pidfile);
    }
    return count;
}

function restart_count() {
    let count = 0;
    if (fs.stat(UDPSPEEDER_LOG_DIR) == null)
        return count;

    let output = command_output_from_args([ "find", UDPSPEEDER_LOG_DIR, "-maxdepth", "1", "-type", "f", "-name", "*.log" ]);
    for (let path in split(output, "\n")) {
        path = trim(as_string(path));
        if (path == "")
            continue;
        let data = fs.readfile(path);
        if (data == null)
            continue;
        for (let line in split(data, "\n"))
            if (match(as_string(line), /udpspeeder for rule .* exited with code/) != null)
                count++;
    }
    return count;
}

function status_json() {
    let sections = enabled_udpspeeder_sections();
    let configured = length(sections) > 0;
    let provider = provider_available();
    let pkg = package_installed();
    let version = pkg || provider ? package_version() : "not installed";
    if (version == "")
        version = "unknown";

    let expected = length(sections);
    let running = live_pid_count(UDPSPEEDER_CHILD_PID_DIR);
    let supervisors = live_pid_count(UDPSPEEDER_PID_DIR);
    let restarts = restart_count();
    let standalone_enabled = standalone_service_enabled();
    let standalone_running = standalone_service_running();
    let conflict = running > expected || standalone_running;
    let unstable = configured && restarts > 0;
    let ready = configured &&
        provider &&
        !standalone_running &&
        !conflict &&
        !unstable &&
        expected > 0 &&
        running == expected;

    let message = "udpspeeder provider status is normal";
    if (configured && !provider)
        message = "action=udpspeeder is configured, but udpspeeder is not available at " + UDPSPEEDER_BIN;
    else if (configured && standalone_running)
        message = "standalone udpspeeder service is active together with Forkop action=udpspeeder; port conflicts are possible";
    else if (running > expected || supervisors > expected)
        message = "unexpected Forkop-managed udpspeeder processes are running";
    else if (configured && !ready)
        message = "action=udpspeeder is configured, but the Forkop-managed udpspeeder runtime is not ready";
    else if (!configured && !provider)
        message = "udpspeeder is not installed; action=udpspeeder is unavailable";

    write_json({
        installed: provider,
        package_installed: pkg,
        provider_available: provider,
        provider_path: UDPSPEEDER_BIN,
        version,
        configured,
        enabled_rule_count: expected,
        expected_process_count: expected,
        running_process_count: running,
        supervisor_process_count: supervisors,
        restart_count: restarts,
        runtime_unstable: unstable,
        standalone_service_enabled: standalone_enabled,
        standalone_service_running: standalone_running,
        listen_address: UDPSPEEDER_LISTEN_ADDRESS,
        port_base: int(UDPSPEEDER_PORT_BASE),
        ready,
        conflict,
        status_message: message
    });
}

function check_json() {
    write_json({
        udpspeeder_installed: provider_available(),
        udpspeeder_package_installed: package_installed(),
        udpspeeder_provider_path: UDPSPEEDER_BIN
    });
}

let mode = ARGV[0] || "";

if (mode == "start-runtime")
    start_runtime();
else if (mode == "stop-runtime")
    stop_runtime();
else if (mode == "supervisor")
    supervisor(ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5], ARGV[6], ARGV[7], ARGV[8], ARGV[9], ARGV[10]);
else if (mode == "status")
    status_json();
else if (mode == "check")
    check_json();
else if (mode == "installed" || mode == "provider-available")
    exit(provider_available() ? 0 : 1);
else if (mode == "package-installed")
    exit(package_installed() ? 0 : 1);
else if (mode == "package-version")
    print(package_version(), "\n");
else if (mode == "enabled-rule-count")
    print(enabled_rule_count(), "\n");
else {
    warn("Usage: providers/udpspeeder/runtime.uc <start-runtime|stop-runtime|status|check|installed|package-installed|package-version> ...\n");
    exit(1);
}
