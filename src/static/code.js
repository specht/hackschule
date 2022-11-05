var editor = null;
var term = null;
var fitAddon = null;
var process_running = false;
var ws = null;
var input = null;
var message_queue = [];
var timerId = null;
var shown_passed_modal = false;
window.interval = null;
window.message_to_append = null;
window.message_to_append_index = 0;
window.message_to_append_timestamp = 0.0;
window.audio = new Audio();
window.audio_queue = [];
window.ivr_analysis = null;

jQuery.extend({
    getQueryParameters : function(str) {
        return (str || document.location.search).replace(/(^\?)/,'').split("&").map(function(n){
            return n = n.split("="), this[n[0]] = n[1], this
        }.bind({}))[0];
    }
});

function show_error_message(message)
{
    var div = $('<div>').css('text-align', 'center').css('padding', '15px').addClass('bg-light text-danger').html(message);
    $('.api_messages').empty();
    $('.api_messages').append(div).show();
}

function show_success_message(message)
{
    var div = $('<div>').css('text-align', 'center').css('padding', '15px').addClass('bg-light text-success').html(message);
    $('.api_messages').empty();
    $('.api_messages').append(div).show();
}

function api_call(url, data, callback, options)
{
    if (typeof(options) === 'undefined')
        options = {};

    if (typeof(window.please_wait_timeout) !== 'undefined')
        clearTimeout(window.please_wait_timeout);

    if (options.no_please_wait !== true)
    {
        // show 'please wait' message after 500 ms
        (function() {
            window.please_wait_timeout = setTimeout(function() {
                var div = $('<div>').css('text-align', 'center').css('padding', '15px').addClass('text-muted').html("<i class='fa fa-cog fa-spin'></i>&nbsp;&nbsp;Einen Moment bitte...");
                $('.api_messages').empty().show();
                $('.api_messages').append(div);
            }, 500);
        })();
    }

    var jqxhr = jQuery.post({
        url: url,
        data: JSON.stringify(data),
        contentType: 'application/json',
        dataType: 'json'
    });

    jqxhr.done(function(data) {
        clearTimeout(window.please_wait_timeout);
        $('.api_messages').empty().hide();
        if (typeof(callback) !== 'undefined')
        {
            data.success = true;
            callback(data);
        }
    });

    jqxhr.fail(function(http) {
        clearTimeout(window.please_wait_timeout);
        $('.api_messages').empty();
        if (typeof(callback) !== 'undefined')
        {
            var error_message = 'unknown_error';
            try {
                error_message = JSON.parse(http.responseText)['error'];
            } catch(err) {
            }
            console.log(error_message);
            callback({success: false, error: error_message});
        }
    });
}

function perform_logout()
{
    api_call('/api/logout', {}, function(data) {
        if (data.success)
            set_sid_cookie(data.remaining_sids);
    });
}

function teletype() {
    var messages = $('#messages');
    var div = messages.children().last();
    var t = Date.now() / 1000.0;
    while ((window.message_to_append_index < window.message_to_append.length) && window.message_to_append_index < (t - window.message_to_append_timestamp) * window.rate_limit)
    {
        var c = document.createTextNode(window.message_to_append.charAt(window.message_to_append_index));
        div.append(c);
        window.message_to_append_index += 1;
    }
    if (window.message_to_append_index >= window.message_to_append.length)
    {
        clearInterval(window.interval);
        window.interval = null;
        window.message_to_append = null;
        if (message_queue.length > 0)
            setTimeout(handle_message, 0);
    }
    $("html, body").stop().animate({ scrollTop: $(document).height() }, 0);
}

function handle_message()
{
    if (message_queue.length === 0 || window.interval !== null || window.message_to_append !== null)
        return;
    var message = message_queue[0];
    message_queue = message_queue.slice(1);
    which = message.which;
    msg = message.msg;
    timestamp = message.timestamp;
    var messages = $('#messages');
    var div = messages.children().last();
    if ((which === 'note') || (which === 'error') || (!div.hasClass(which)))
    {
        div = $('<div>').addClass('message ' + which);
        messages.append(div);
        $('<div>').addClass('timestamp').html(timestamp).appendTo(div);
        if (which === 'server' || which == 'client')
            $('<div>').addClass('tick').appendTo(div);
    }
    if (which === 'server' || which === 'client')
    {
        window.message_to_append = msg;
        if (which === 'client')
            window.message_to_append += "\n";
        window.message_to_append_timestamp = Date.now() / 1000.0;
        window.message_to_append_index = 0;
        var d = 1000 / window.rate_limit;
        if (d < 1)
            d = 1;
        console.log(d);
        window.interval = setInterval(teletype, d);
    }
    else
    {
        div.append(document.createTextNode(msg));
        div.append("<br />");
        if (message_queue.length > 0)
            setTimeout(handle_message, 0);
    }

    $("html, body").stop().animate({ scrollTop: $(document).height() }, 400);
}

function append(which, msg)
{
    var d = new Date();
    var timestamp = ('0' + d.getHours()).slice(-2) + ':' +
                    ('0' + d.getMinutes()).slice(-2) + ':' +
                    ('0' + d.getSeconds()).slice(-2);
    message_queue.push({which: which, timestamp: timestamp, msg: msg});
    if (message_queue.length === 1)
        setTimeout(handle_message, 0);
}

function append_client(msg)
{
    append('client', msg);
}

function append_server(msg)
{
    append('server', msg);
}

function append_note(msg)
{
    append('note', msg);
}

function append_error(msg)
{
    append('error', msg);
}

function keepAlive() {
    var timeout = 20000;
    if (ws.readyState == ws.OPEN) {
        ws.send('');
    }
    (function() {
        timerId = setTimeout(keepAlive, timeout);
    })();
}

function push_message(s, color, delay) {
    if (typeof(color) === 'undefined')
        color = 'warning';
    $('.info').stop();
    $('.info').removeClass('bg-warning');
    $('.info').removeClass('bg-success');
    $('.info').addClass('bg-' + color);
    $('.info').css('color', 'unset');
    if (color === 'success')
        $('.info').css('color', '#fff');
    $('.info').html(s).slideDown();
    if (delay > 0)
        $('.info').delay(delay).slideUp();
}

function handle_started() {
    $('#run').removeClass('btn-success').addClass('btn-danger').html("<i class='fa fa-stop'></i>&nbsp;&nbsp;Abbrechen").prop('disabled', false);
    window.audio.pause();
    window.audio_queue = [];
    process_running = true;
    if (!$('#easy6502').is(':visible')) {
        if (!$('#screen').is(':visible'))
            term.focus();
    }
}

function handle_stopped() {
    window.audio.pause();
    window.audio_queue = [];
    $('#run').removeClass('btn-danger').addClass('btn-success').html("<i class='fa fa-play'></i>&nbsp;&nbsp;Ausführen");
    $('#editor').prop('disabled', false);
    process_running = false;
    editor.setReadOnly(false);
    term.write("\r\n");
    term.blur();
    if ($('body').width() >= 768)
        editor.focus();
    $('#screen img.pixelflut').removeAttr('src').attr('src', '/pixelflut/?' + Date.now());
    $('#screen img.canvas').removeAttr('src').attr('src', '/canvas/' + session_user_email + '/?' + Date.now());
}

function start_audio_queue() {
    if (window.audio_queue.length === 0)
        return;
    if (window.audio.paused) {
        let item = window.audio_queue.shift();
        if (item.command === 'hangup') {
            console.log("HANGING UP!")
            $('#run').trigger('click');
        } else {
            window.audio.src = item.path;
            window.audio.play();
        }
    }
}

function refresh_active_ivr_codes() {
    api_call('/api/get_my_ivr', {}, function(data) {
        $('#ivr_div_list').empty();
        let all_published_sha1 = [];
        if (data.rows.length === 0) {
            $('#ivr_div_list').append("<p>Du hast noch keine Spiele veröffentlicht.</p>");
        } else {
            $('#ivr_div_list').append("<p>Hier siehst du eine Liste deiner momentan veröffentlichten Telefonspiele:</p>");
            let table = $(`<table class='table table-responsive'>`);
            let row = $("<tr>");
            row.append($("<th>").text('Code'));
            row.append($("<th>").text('Programm'));
            row.append($("<th>").text(''));
            row.append($("<th>").text(''));
            table.append(row);
            for (let entry of data.rows) {
                all_published_sha1.push(entry.sha1);
                let row = $("<tr>");
                row.append($("<td>").html(`<b>${entry.code}</b>`));
                row.append($("<td>").append($('<a>').text(`${entry.sha1}`).attr('href', `/task/telefonspiel/${entry.sha1}`)));
                row.append($("<td>").append($('<a>').addClass('btn btn-success btn-sm').attr('href', `tel:+493075438953,${entry.code}`).html(`Anrufen`)));
                let bu_unpublish = $('<button>').addClass('btn btn-danger btn-sm').html(`Löschen`).data('sha1', entry.sha1);
                bu_unpublish.on('click', function(e) {
                    let button = $(e.target).closest('button');
                    let sha1 = button.data('sha1');
                    api_call('/api/unpublish_ivr', {sha1: sha1}, function(data) {
                        if (data.success) {
                            refresh_active_ivr_codes();
                        }
                    });
                });
                row.append($("<td>").append(bu_unpublish));
                table.append(row);
            }
            $('#ivr_div_list').append(table);
        }

        $('#ivr_div').empty();
        if (window.ivr_sha1 !== null && window.ivr_analysis !== null) {
            if (all_published_sha1.indexOf(window.ivr_sha1) < 0) {
                let button = $(`<button class='btn btn-success' style='margin-right: 10px;'>Spiel veröffentlichen</button>`);
                $('#ivr_div').append(button);
                button.on('click', function(e) {
                    api_call('/api/publish_ivr', {sha1: window.ivr_sha1}, function(data) {
                        if (data.success) {
                            refresh_active_ivr_codes();
                        }
                    });
                });
            } else {
                $('#ivr_div').append($('<p>').text('Diese Version des Spiels ist bereits veröffentlicht.'))
            }
            let button = $(`<button class='btn btn-secondary' style='margin-right: 10px;'>Texte einsprechen</button>`);
            $('#ivr_div').append(button);
            button.on('click', function(e) {
                $('#ivrSentencesModalGameTitle').text(window.ivr_analysis.title);
                $('#sentences-tbody').empty();
                for (let sentence of window.ivr_analysis.sentences) {
                    let has_var = sentence.indexOf('[[[') >= 0;
                    let row = $('<tr>');
                    row.append($('<td>').text(sentence).css('white-space', 'break-spaces').css('font-family', 'Roboto Condensed').css('color', has_var ? '#888' : 'unset'));
                    let bu_speak = $(`<button class='btn btn-xs btn-success'>Vorlesen</button>`).data('text', sentence);
                    row.append($('<td>').append(bu_speak));
                    bu_speak.on('click', function(e) {
                        let button = $(e.target).closest('button');
                        api_call('/api/say_sentence', {sentence: button.data('text')}, function(data) {
                            if (data.success) {
                                window.audio_queue = [];
                                window.audio.pause();
                                window.audio_queue.push({path: data.path_hd});
                                start_audio_queue();
                            }
                        })
                    });
                    $('#sentences-tbody').append(row);
                }
                $('#ivrSentencesModal').modal('show');
            });
        } else {
            $('#ivr_div').append($(`<p>Wenn du dein Spiel veröffentlichen möchtest, musst du ihm einen Namen geben. Verwende dafür die Methode <code>set_title</code>.</p>`))
        }
    });
}

function fixUri(slug, sha1, analysis) {
    console.log('fixUri', slug, sha1, analysis);
    if (typeof(analysis) !== 'undefined') {
        if (analysis.title === null || typeof(analysis.title) === 'undefined')
            analysis = null;
        window.ivr_analysis = analysis;
        
    } else {
        window.ivr_analysis = null;
    }
    history.replaceState({}, null, '/task/' + slug + '/' + sha1);
    if (window.got_ivr) {
        console.log(`have ivr for ${sha1}`);
        window.ivr_sha1 = sha1;
        refresh_active_ivr_codes();
    }
}

function setup_ws(ws)
{
    ws.onopen = function () {
        console.log('ws.onopen');
        keepAlive();
        ws.send(JSON.stringify({
            action: 'run',
            slug: window.slug,
            script: window.launch_this_script
        }));
    }

    ws.onclose = function () {
        console.log('ws.onclose');
        clearTimeout(timerId);
    }

    ws.onmessage = function (msg) {
        data = JSON.parse(msg.data);
        // console.log(data);
        if (data.hello === 'world')
        {
            window.rate_limit = data.rate_limit;
        }
        else if (data.status === 'started')
        {
            handle_started();
        }
        else if (data.status === 'stopped')
        {
            handle_stopped();
        }
        else if (data.status === 'passed')
        {
            $('#already-solved').show();
            if (!shown_passed_modal)
                $('#passedModal').modal('show');
            shown_passed_modal = true;
            push_message('Herzlichen Glückwunsch, dein Programm ist korrekt!', 'success', 0);
        }
        else if (typeof(data.connection_error) !== 'undefined')
        {
            append_error('Failed connection attempt to ' + data.host + ' ' + (data.tls ? '(TLS) ' : '') + 'on port ' + data.port + ' (' + data.connection_error + ')');
        }
        else if (typeof(data.message) !== 'undefined')
        {
            push_message(data.message, data.color, 0);
        }
        else if (typeof(data.stdout) !== 'undefined')
        {
            term.write(data.stdout);
        }
        else if (typeof(data.stderr) !== 'undefined')
        {
            term.write(data.stderr);
        }
        else if (typeof(data.dungeon) !== 'undefined')
        {
            enqueue_dungeon_command(data.dungeon);
        }
        else if (typeof(data.ivr) !== 'undefined')
        {
            if (data.ivr.command === 'reset_audio_queue') {
                console.log("clearing audio queue!")
                window.audio_queue = [];
                window.audio.pause();
            } else {
                window.audio_queue.push(data.ivr);
                start_audio_queue();
            }
        }
        else if (typeof(data.script_sha1) !== 'undefined')
        {
            fixUri(window.slug, data.script_sha1, data.analysis);
        }
        else if (typeof(data.zpl_png) !== 'undefined')
        {
            $('#zpl_png img').attr('src', data.zpl_png);
            $('.bu-print-label').prop('disabled', false).removeClass('btn-outline-secondary').addClass('btn-outline-success');
            let parts = data.zpl_png.split('/');
            window.print_label_tag = parts[parts.length - 1].replace('.png', '');

        }
    }
    window.audio.onended = function() {
        start_audio_queue();
    }
}

function sendInput()
{
    var msg = input.val();
    append_client(msg);
    ws.send(JSON.stringify({action: 'send', message: msg}))
    input.val("");
}

function launch_script(script)
{
    $('.info').hide();
    $('#run').prop('disabled', true);
    $('#editor').prop('disabled', true);
    editor.setReadOnly(true);
    var ws_uri = 'ws://' + location.host + '/ws';
    if (location.host !== 'localhost:8025')
        ws_uri = 'wss://' + location.host + '/ws';
    ws = new WebSocket(ws_uri);
    setup_ws(ws);
    window.launch_this_script = script;
    $('.mi-load-latest-draft').removeClass('disabled');
    $('.bu-print-label').prop('disabled', true).removeClass('btn-outline-success').addClass('btn-outline-secondary');
}

function store_script(script)
{
    api_call('/api/store_script', {
        slug: window.slug,
        script: script}, function(data) {
            fixUri(window.slug, data.sha1, data.analysis);
        });
}

function kill_script()
{
    ws.send(JSON.stringify({
        action: 'kill'
    }));
}
