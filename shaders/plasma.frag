// simple plasma test shader (shadertoy image format)
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
    float t = iTime * 0.6;
    float v = 0.0;
    v += sin(uv.x * 3.0 + t);
    v += sin((uv.y + uv.x) * 2.5 - t * 1.3);
    v += sin(length(uv * 3.0) - t * 2.0);
    v += sin(length(uv - vec2(sin(t * 0.7), cos(t * 0.5))) * 4.0);
    vec3 col = 0.5 + 0.5 * cos(vec3(0.0, 2.094, 4.188) + v * 1.5 + t * 0.5);
    fragColor = vec4(col, 1.0);
}
