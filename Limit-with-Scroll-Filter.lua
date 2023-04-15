obs = obslua
bit = require("bit")

source_def = {}
source_def.id = "Limit-with-Scroll"
source_def.type = obs.OBS_SOURCE_TYPE_FILTER
source_def.output_flags = bit.bor(obs.OBS_SOURCE_VIDEO, obs.OBS_SOURCE_CUSTOM_DRAW)

source_def.get_name = function()
	return "Limit with Scroll"
end


function script_description()
	return "This adds a new filter to OBS that limits the size of a source. If the source exceeds this size, it will be cropped and will periodically scroll to show the entire source. Intended for text that needs to fit in a limited area."
end

source_def.create = function(settings, source)
	local inlineEffect = [[
		uniform float4x4 ViewProj;
		uniform texture2d image;

		uniform float xOff;
		uniform float yOff;
		uniform float xMult;
		uniform float yMult;

		sampler_state def_sampler {
			Filter   = Linear;
			AddressU = Border;
			AddressV = Border;
			BorderColor = 00000000;
		};

		struct VertInOut {
			float4 pos : POSITION;
			float2 uv  : TEXCOORD0;
		};

		VertInOut VSDefault(VertInOut vert_in)
		{
			VertInOut vert_out;
			vert_out.pos = mul(float4(vert_in.pos.xyz, 1.0), ViewProj);
			vert_out.uv  = vert_in.uv;
			return vert_out;
		}

		float4 PSAddOffset(VertInOut vert_in) : TARGET
		{
			vert_in.uv.x = (vert_in.uv.x * xMult) - xOff;
			vert_in.uv.y = (vert_in.uv.y * yMult) - yOff;
			float4 rgba = image.Sample(def_sampler, vert_in.uv);// * float4(0, 1.0, 1.0, 1.0);
			if (rgba.a > 0){
				rgba.rgb /= rgba.a;
			}
			return rgba;
		}

		technique Draw
		{
			pass
			{
				vertex_shader = VSDefault(vert_in);
				pixel_shader  = PSAddOffset(vert_in);
			}
		}
	]]

	local filter = {}
	filter.context = source
	filter.params = {}
	
	-- Internal state
	filter.state = 0
	filter.offset = 0
	filter.timer = 0
	
	obs.obs_enter_graphics()
	obs.gs_effect_destroy(filter.effect)
	filter.effect = obs.gs_effect_create(inlineEffect, "offsetEffect", nil)
	if filter.effect ~= nil then
		filter.params.xOff = obs.gs_effect_get_param_by_name(filter.effect, 'xOff')
		filter.params.yOff = obs.gs_effect_get_param_by_name(filter.effect, 'yOff')
		filter.params.xMult = obs.gs_effect_get_param_by_name(filter.effect, 'xMult')
		filter.params.yMult = obs.gs_effect_get_param_by_name(filter.effect, 'yMult')
	end
	obs.obs_leave_graphics()
	
	set_render_size(filter)

	source_def.update(filter, settings)
	return filter
end

source_def.destroy = function(filter)
	if filter.effect ~= nil then
        obs.obs_enter_graphics()
        obs.gs_effect_destroy(filter.effect)
        obs.obs_leave_graphics()
    end
end

function set_render_size(filter)
    target = obs.obs_filter_get_target(filter.context)

    local width, height
    if target == nil then
        width = 0
        height = 0
    else
        width = obs.obs_source_get_base_width(target)
        height = obs.obs_source_get_base_height(target)
    end

	filter.image_width = width
	filter.image_height = height
	
    filter.width = width
    filter.height = height
	
	if filter.direction == 0 then
		filter.width = filter.maxSize or width
	else
		filter.height = filter.maxSize or height
	end
	
end

source_def.video_render = function(filter, effect)
	set_render_size(filter)
	obs.obs_source_process_filter_begin(filter.context, obs.GS_RGBA, obs.OBS_NO_DIRECT_RENDERING)
	
	if filter.direction == 0 then
		obs.gs_effect_set_float(filter.params.xOff, -filter.offset / filter.image_width)
		obs.gs_effect_set_float(filter.params.yOff, 0)
	else
		obs.gs_effect_set_float(filter.params.xOff, 0)
		obs.gs_effect_set_float(filter.params.yOff, -filter.offset / filter.image_height)
	end
	
	obs.gs_effect_set_float(filter.params.xMult, filter.width / filter.image_width)
	obs.gs_effect_set_float(filter.params.yMult, filter.height / filter.image_height)

    obs.obs_source_process_filter_end(filter.context, filter.effect, filter.width, filter.height)
end

source_def.video_tick = function(filter, deltaTime)
    set_render_size(filter)

	if ((filter.direction == 0) and filter.image_width or filter.image_height) <= filter.maxSize then
		-- Image is not larger than limit, so no scrolling is needed
		filter.state = 0
		filter.timer = 0
		filter.offset = 0
	else	
		filter.state = filter.state or 0	
		if filter.state == 0 then
			-- Wait at start
			filter.timer = (filter.timer or 0) + deltaTime
			if filter.timer > (filter.waitAtStart or 5) then
				filter.state = 1
			end
		elseif filter.state == 1 then
			-- Move to end
			filter.offset = (filter.offset or 0) + filter.speed * deltaTime
			local limit = ((filter.direction == 0) and filter.image_width or filter.image_height) - filter.maxSize
			if filter.offset >= limit then
				filter.offset = limit
				filter.state = 2
				filter.timer = 0
			end
		elseif filter.state == 2 then
			-- Wait at end
			filter.offset = ((filter.direction == 0) and filter.image_width or filter.image_height) - filter.maxSize
			filter.timer = (filter.timer or 0) + deltaTime
			if filter.timer > (filter.waitAtEnd or 5) then
				filter.state = 0
				filter.timer = 0
				filter.offset = 0
			end
		else
			filter.state = 0
			filter.offset = 0
		end
	end
end

----------------------
source_def.get_properties = function(settings)
	props = obs.obs_properties_create()

	obs.obs_properties_add_float(props, "speed", "Speed (px/second)", 1, 10000, 1)
	
	local list = obs.obs_properties_add_list(props, "direction", "Direction", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	obs.obs_property_list_add_int(list, "Horizontal", 0)
	obs.obs_property_list_add_int(list, "Vertical", 1)
	 
    obs.obs_properties_add_int(props, "maxSize", "Max Size", 1, 10000, 10)
	obs.obs_properties_add_float(props, "waitAtStart", "Wait at Start", 0.1, 10000, 0.2)
	obs.obs_properties_add_float(props, "waitAtEnd", "Wait at End", 0.1, 10000, 0.2)

    return props
end

source_def.get_defaults = function(settings)
    obs.obs_data_set_default_double(settings, "speed", 60)
	obs.obs_data_set_default_int(settings, "direction", 0)
    obs.obs_data_set_default_int(settings, "maxSize", 400)
	obs.obs_data_set_default_double(settings, "waitAtStart", 4)
	obs.obs_data_set_default_double(settings, "waitAtEnd", 4)
end

source_def.update = function(filter, settings)
    filter.speed = obs.obs_data_get_double(settings, "speed")
	filter.direction = obs.obs_data_get_int(settings, "direction")
    filter.maxSize = obs.obs_data_get_int(settings, "maxSize")
	filter.waitAtStart = obs.obs_data_get_double(settings, "waitAtStart")
	filter.waitAtEnd = obs.obs_data_get_double(settings, "waitAtEnd")

    set_render_size(filter)
end
-----------------------

source_def.get_width = function(filter)
	return filter.width
end

source_def.get_height = function(filter)
	return filter.height
end


obs.obs_register_source(source_def)
