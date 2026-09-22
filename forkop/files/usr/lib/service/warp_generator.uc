#!/usr/bin/env ucode

let fs = require("fs");
let math = require("math");
let common = require("core.common");

let as_string = common.as_string;
let write_json = common.write_json;

function trim(str) {
    return replace(as_string(str), /^[ \t\r\n]+|[ \t\r\n]+$/g, "");
}

function exec_output(command) {
    let pipe = fs.popen(command, "r");
    if (!pipe) return "";
    let data = pipe.read("all");
    pipe.close();
    return data == null ? "" : trim(data);
}

const PORTS = [
    500, 854, 859, 864, 878, 880, 890, 891, 894, 903, 908, 928, 934, 939,
    942, 943, 945, 946, 955, 968, 987, 988, 1002, 1010, 1014, 1018, 1070,
    1074, 1180, 1387, 1701, 1843, 2371, 2408, 2506, 3138, 3476, 3581, 3854,
    4177, 4198, 4233, 4500, 5279, 5956, 7103, 7152, 7156, 7281, 7559, 8319,
    8742, 8854, 8886
];

const PREFIXES = [
    "162.159.192.",
    "162.159.195.",
    "188.114.96.",
    "188.114.97.",
    "188.114.98."
];

const ENDPOINTS = [
    "https://warp-gen.netlify.app/",
    "https://warp-vercel-chi.vercel.app/api/warp-data",
    "https://warp-vercel-murex.vercel.app/api/warp-data",
    "https://www.warp-generator.workers.dev",
    "https://warp.sub-aggregator.workers.dev"
];

function generate_warp() {
    let last_error = "Failed to connect to WARP generation endpoints";
    let parsed = null;

    for (let url in ENDPOINTS) {
        let cmd = "curl -s --connect-timeout 4 --max-time 6 -H 'X-Client: WARP' " + url + " 2>/dev/null";
        let out = exec_output(cmd);
        if (out == "")
            continue;

        try {
            let data = json(out);
            if (data && data.privKey && data.client_ipv4) {
                parsed = data;
                break;
            }
        }
        catch (e) {
            last_error = e.message || "Invalid JSON from generator";
        }
    }

    if (!parsed) {
        write_json({
            success: false,
            message: last_error
        });
        return 1;
    }

    let prefix = PREFIXES[math.rand() % length(PREFIXES)];
    let host_num = (math.rand() % 10) + 1;
    let server_address = prefix + host_num;
    let server_port = PORTS[math.rand() % length(PORTS)];

    let local_address = parsed.client_ipv4;
    if (!match(local_address, /\/\d+$/))
        local_address += "/32";

    if (parsed.client_ipv6) {
        let ipv6 = parsed.client_ipv6;
        if (!match(ipv6, /\/\d+$/))
            ipv6 += "/128";
        local_address += ", " + ipv6;
    }

    let result = {
        success: true,
        local_address: local_address,
        private_key: parsed.privKey,
        peer_public_key: parsed.peer_pub || "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
        server_address: server_address,
        server_port: as_string(server_port),
        awg_jc: "4",
        awg_jmin: "40",
        awg_jmax: "70",
        awg_s1: "0",
        awg_s2: "0",
        awg_s3: "0",
        awg_s4: "0",
        awg_h1: "1",
        awg_h2: "2",
        awg_h3: "3",
        awg_h4: "4",
        awg_mtu: "1280",
        awg_keepalive: "25",
        awg_version: "2.0"
    };

    write_json(result);
    return 0;
}

if (ARGV[0] == "generate-warp" || length(ARGV) == 0) {
    exit(generate_warp());
}
