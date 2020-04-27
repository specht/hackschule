window.pixelflut_width = 256;
window.pixelflut_height = 144;
window.pixelflut_scale = 2;
window.pixelflut_image = null;

function resize_pixelflut() {
    let width = $('#screen').width();
    let height = $('#screen').height();
    // determine dungeon_scale
    pixelflut_scale = 1;
    for (i = 2; i <= 4; i += 1)
        if (pixelflut_width * i < width && pixelflut_height * i < height)
            pixelflut_scale = i;
    $('#sprite_container img').css('width', '' + pixelflut_width * pixelflut_scale + 'px');
    $('#sprite_container img').css('height', '' + pixelflut_height * pixelflut_scale + 'px');
    // shift sprite_container
    let shift_x = (width / 2 - pixelflut_scale * pixelflut_width / 2);
    let shift_y = (height / 2 - pixelflut_scale * pixelflut_height / 2);
    $('#sprite_container img').css('left', '' + shift_x + 'px');
    $('#sprite_container img').css('top', '' + shift_y + 'px');
}

function load_pixelflut() {
    pixelflut_image = $('<img>').attr('src', '/pixelflut/?' + + Date.now()).addClass('pixelflut');
    $('#sprite_container').empty().append(pixelflut_image);
}
