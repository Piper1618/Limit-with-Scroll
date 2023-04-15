# Limit with Scroll

This script adds a new filter to [OBS](https://obsproject.com/) that can be applied to any video source (including still images or text). The filter creates a maximum size for the source. If the source extends beyond that limit, it will be cropped down and will scroll periodically to show its entire contents. This was designed for text sources where the text might be too large to fit into the required space.

The only file that's needed is "Limit-with-Scroll-Filter.lua". Once the file is on your local drive, the script can be imported from inside OBS by navigating to Tools -> Scripts.

This was tested on OBS version 28.0.2.

# Settings

Once you've added the "Limit with Scroll" filter to a source, the following settings can be set.

**Speed:** How fast the source should scroll, in pixels per second.

**Direction:** Decide whether to limit the source vertically or horizontally.

**Max Size:** The largest allowed size in the limited direction. If the source is smaller than this size, no scrolling will occur.

**Wait at Start:** How long, in seconds, the source should wait at the left/top of the source before beginning to scroll.

**Wait at End:** The source will stop at the right/bottom of the source and wait this long, in seconds, before snapping back to the beginning.