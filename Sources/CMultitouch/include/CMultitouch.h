// Memory layout of the private MultitouchSupport.framework contact record.
// Functions are resolved at runtime with dlopen/dlsym (see MultitouchBridge.swift),
// so this header only describes data types and never links the private framework.
#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerId;
    int handId;
    MTVector normalized;   // 0...1, origin bottom-left
    float total;           // total capacitance (contact size)
    float pressure;        // force sensor reading
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;     // millimetres
    int field14;
    int field15;
    float density;
} MTTouch;

#endif
