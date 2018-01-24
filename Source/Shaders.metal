#include <metal_stdlib>
#import "ShaderTypes.h"

using namespace metal;

float3 toRectangular(float3 sph) {
    return float3(
                  sph.x * sin(sph.z) * cos(sph.y),
                  sph.x * sin(sph.z) * sin(sph.y),
                  sph.x * cos(sph.z));
}

float3 toSpherical(float3 rec) {
    return float3(length(rec),
                  atan2(rec.y,rec.x),
                  atan2(sqrt(rec.x*rec.x+rec.y*rec.y), rec.z));
}

float3 lerp(float3 a, float3 b, float w) { return a + w*(b-a); }

float3 hsv2rgb(float3 c) {
    return lerp(saturate((abs(fract(c.x + float3(1,2,3)/3) * 6 - 3) - 1)),1,c.y) * c.z;
}

// ===========================================================================================

float escape(float3 position, Control control) {
    float3 z = position;
    float trap = 0.0;
    float r = 0.0;
    float theta,phi,zr,sineTheta;
    int i;
    
    for(i=0;i<129;i++) {
        if (i >= control.colors) return 1.0;
        r = length(z);
        if(r > control.bailout) break;
        trap += r;

        theta = control.power * atan2(sqrt(z.x*z.x+z.y*z.y),z.z);
        phi = control.power * atan2(z.y,z.x);
        sineTheta = sin(theta);
        zr = pow(r,control.power);
        z = float3(zr * sineTheta * cos(phi) + position.x,
                   zr * sin(phi) * sineTheta + position.y,
                   zr * cos(theta) + position.z);
    }
    
    return 0.25 * ((trap * log(control.minimumStepDistance))/(10.0 * float(i)));
}

// ===========================================================================================

float DE(float3 position, Control control) {
    float3 z = position;
    float dr = 1.0;
    float r = 0.0;
    float theta,phi,zr,sineTheta;

    for(int i=0;i<64;++i) {
        if(i > control.iterations) break;
        r = length(z);
        if(r > control.bailout) break;

        theta = control.power * atan2(sqrt(z.x*z.x+z.y*z.y),z.z);
        phi = control.power * atan2(z.y,z.x);
        sineTheta = sin(theta);
        zr = pow(r,control.power);
        z = float3(zr * sineTheta * cos(phi) + position.x,
                   zr * sin(phi) * sineTheta + position.y,
                   zr * cos(theta) + position.z);
        dr = ( pow(r, control.power - 1.0) * control.power * dr ) + 1.0;
    }

    return 0.5 * log(r)*r/dr;
}

float3 normalOf(float3 pos, Control control) {
    float eps = 0.01;   // float eps = abs(d_est_u/100.0);
    return normalize(float3(DE( pos + float3(eps,0,0), control) - DE(pos - float3(eps,0,0), control),
                            DE( pos + float3(0,eps,0), control) - DE(pos - float3(0,eps,0), control),
                            DE( pos + float3(0,0,eps), control) - DE(pos - float3(0,0,eps), control)  ));
}

float phong(float3 position, Control control) {
    float3 k = (position - control.light) + (control.camera - control.light);
    float3 h = k / length(k);
    return 0.0-dot(h,normalOf(position,control));
}

// ===========================================================================================

float3 march(float3 direction, Control control) {
    float3 from = control.camera;
    float totalDistance = 0.0;
    float dist;
    float3 position;
    float d_est_u = DE(from,control);
    float distCutOff = max(d_est_u * 2.0,4.0);
    
    for(int steps=0;steps <  control.maxRaySteps;steps++) {
        position = float3(from.x + (direction.x * totalDistance),
                          from.y + (direction.y * totalDistance),
                          from.z + (direction.z * totalDistance));
        dist = DE(position,control);
        totalDistance += dist;
        
        if(totalDistance > distCutOff) return float3(0.0,0.0,0.0);
        if(dist < control.minimumStepDistance) {
            return float3(escape(position,control),
                          0.6,
                          0.7 * (1.0 - float(steps)/float(control.maxRaySteps)) + 0.3 * phong(position,control));
            
            //return float3(escape(position,control),  0.55,  (1.0 - float(steps)/float(control.maxRaySteps)));
        }
    }
    
    return float3(0,0,0);
}

// ===========================================================================================

kernel void rayMarchShader
(
    texture2d<float, access::write> outTexture [[texture(0)]],
    constant Control &control [[buffer(0)]],
    uint2 p [[thread_position_in_grid]])
{
    float2 uv = float2(float(p.x) / float(control.size), float(p.y) / float(control.size));     // map pixel to 0..1
    float3 viewVector = control.focus - control.camera;
    float3 topVector = toSpherical(viewVector);
    topVector.z += 1.5708;
    topVector = toRectangular(topVector);
    float3 sideVector = cross(viewVector,topVector);
    sideVector = normalize(sideVector) * length(topVector);
    
    float dx = control.zoom * (uv.x - 0.5);
    float dy = (-1.0) * control.zoom * (uv.y - 0.5);

    float3 direction = normalize((sideVector * dx) + (topVector * dy) + viewVector);
    
    float3 color = hsv2rgb( march(direction, control));
    
    outTexture.write(float4(color,1),p);
}

