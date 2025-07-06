#ifdef GL_ES
precision mediump float;
#endif

attribute vec4 love_Vertex; // Vertex position in object space
attribute vec4 love_Color; // Vertex color
attribute vec2 love_TexCoord; // Texture coordinate

varying vec4 v_color;
varying vec2 v_texCoord;

uniform mat4 love_ProjectionMatrix;
uniform mat4 love_ViewMatrix; // In LÖVE 11+, it's ViewMatrix and ModelMatrix separately
uniform mat4 love_ModelMatrix;

void main() {
    v_color = love_Color;
    v_texCoord = love_TexCoord;
    gl_Position = love_ProjectionMatrix * love_ViewMatrix * love_ModelMatrix * love_Vertex;
}
