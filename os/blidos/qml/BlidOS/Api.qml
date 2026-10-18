pragma Singleton
import QtQuick

// Calls into Python: Api.call("wifiNetworks", [true], ok => ..., err => ...).
// Errors without a handler show up as a toast.
QtObject {
    id: api
    property var _pending: ({})
    property int _next: 1
    signal toast(string message)

    function call(name, args, onOk, onErr) {
        var token = _next++
        _pending[token] = { ok: onOk, err: onErr }
        backend.call(token, name, JSON.stringify(args === undefined ? [] : args))
    }

    property Connections _answers: Connections {
        target: backend
        function onFinished(token, ok, json) {
            var p = api._pending[token]
            delete api._pending[token]
            if (!p) return
            var value = JSON.parse(json)
            if (ok) { if (p.ok) p.ok(value) }
            else if (p.err) p.err(value)
            else api.toast(value)
        }
    }
}
