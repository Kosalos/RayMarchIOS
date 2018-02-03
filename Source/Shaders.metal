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

float DE(float3 w, Control control) {
    int iter = 0;
    float trap = 0.0;
    float r = 0.0;
    float dr = 1.0;

    // 0 Bulb 1 --------------------------------------------------------------------------------
    if (control.formula == 0) { // https://github.com/jtauber/mandelbulb/blob/master/mandel8.py
        float theta,phi,pwr,ss;
        
        for(;;) {
            if(++iter == control.iterations) break;

            r = length(w);
            if(r > control.bailout) break;
            trap += r;
            
            theta = atan2(sqrt(w.x * w.x + w.y * w.y), w.z);
            phi = atan2(w.y,w.x);
            pwr = pow(r,control.power);
            ss = sin(theta * control.power);
            
            w.x += pwr * ss * cos(phi * control.power);
            w.y += pwr * ss * sin(phi * control.power);
            w.z += pwr * cos(theta * control.power);
        
            dr = ( pow(r, control.power - 1.0) * control.power * dr ) + 1.0;
        }
    }
    
    // 1 Bulb 2 -----------------------------------------------------------------------------------
    if (control.formula == 1) {
        float dz = 1.0;
        
        for(;;) {
            if(++iter == control.iterations) break;

            r = length(w);
            if(r > control.bailout) break;
            trap += r;
            
            float m2 = r * r;
            float m4 = m2 * m2;
            dz = 8.0 * sqrt(m4 * m2 * r) * dz + 1.0;
            
            float x = w.x; float x2 = x*x; float x4 = x2*x2;
            float y = w.y; float y2 = y*y; float y4 = y2*y2;
            float z = w.z; float z2 = z*z; float z4 = z2*z2;
            float k3 = x2 + z2;
            float k2s = sqrt(pow(k3,control.power));
            float k2 = 1;  if(k2s != 0) k2 = 1.0 / k2s;
            float k1 = x4 + y4 + z4 - 6.0 * y2 * z2 - 6.0 * x2 * y2 + 2.0 * z2 * x2;
            float k4 = x2 - y2 + z2;
            
            w.x +=  64.0 * x * y * z * (x2-z2) * k4 * (x4 - 6.0 * x2 * z2 + z4) * k1 * k2;
            w.y +=  -16.0 * y2 * k3 * k4 * k4 + k1 * k1;
            w.z +=  -8.0 * y * k4 * (x4 * x4 - 28.0 * x4 * x2 * z2 + 70.0 * x4 * z4 - 28.0 * x2 * z2 * z4 + z4 * z4) * k1 * k2;
        
            dr = ( pow(r, control.power - 1.0) * control.power * dr ) + 1.0;
        }
    }
    
    // 2 Bulb 3 -----------------------------------------------------------------------
    if (control.formula == 2) {
        float magnitude, theta_power, r_power, phi, phi_cos, xxyy;
        
        for(;;) {
            if(++iter == control.iterations) break;

            xxyy = w.x * w.x + w.y * w.y;
            magnitude = xxyy + w.z * w.z;
            
            r = sqrt(magnitude);
            if(r > control.bailout) break;
            trap += r;
            
            theta_power = atan2(w.y,w.x) * control.power;
            r_power = pow(r,control.power);
            
            phi = asin(w.z / r);
            phi_cos = cos(phi * control.power);
            w.x += r_power * cos(theta_power) * phi_cos;
            w.y += r_power * sin(theta_power) * phi_cos;
            w.z += r_power * sin(phi * control.power);

            dr = ( pow(r, control.power - 1.0) * control.power * dr ) + 1.0;
        }
    }
    
    // 3 Bulb 4 -----------------------------------------------------------------------
    if (control.formula == 3) {
        float magnitude, theta_power, r_power, phi, phi_sin, xxyy;
        
        for(;;) {
            if(++iter == control.iterations) break;
            
            xxyy = w.x * w.x + w.y * w.y;
            magnitude = xxyy + w.z * w.z;
            
            r = sqrt(magnitude);
            if(r > control.bailout) break;
            trap += r;
            
            theta_power = atan2(w.y,w.x) * control.power;
            r_power = pow(r,control.power);
            
            phi = atan2(sqrt(xxyy), w.z);
            phi_sin = sin(phi * control.power);
            w.x += r_power * cos(theta_power) * phi_sin;
            w.y += r_power * sin(theta_power) * phi_sin;
            w.z += r_power * cos(phi * control.power);
            
            dr = ( pow(r, control.power - 1.0) * control.power * dr ) + 1.0;
        }
    }
    
    // 4 Bulb 5 -----------------------------------------------------------------------
    if (control.formula == 4) {
        float magnitude, theta_power, r_power, phi, phi_cos, xxyy;
        
        for(;;) {
            if(++iter == control.iterations) break;
            
            xxyy = w.x * w.x + w.y * w.y;
            magnitude = xxyy + w.z * w.z;
            
            r = sqrt(magnitude);
            if(r > control.bailout) break;
            trap += r;
            
            theta_power = atan2(w.y,w.x) * control.power;
            r_power = pow(r,control.power);
            
            phi = acos(w.z / r);
            phi_cos = cos(phi * control.power);
            w.x += r_power * cos(theta_power) * phi_cos;
            w.y += r_power * sin(theta_power) * phi_cos;
            w.z += r_power * sin(phi*control.power);
            
            dr = ( pow(r, control.power - 1.0) * control.power * dr ) + 1.0;
        }
    }
    
    return 0.5 * log(r)*r/dr;
}

float oldDE(float3 position, Control control) {
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

