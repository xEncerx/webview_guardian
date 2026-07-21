/*******************************************************************************
    BSD 3-Clause License

    Copyright (c) 2026, xEncerx (webview_guardian Package)
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    1. Redistributions of source code must retain the above copyright notice,
       this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright notice,
       this list of conditions and the following disclaimer in the documentation
       and/or other materials provided with the distribution.
    3. Neither the name of the copyright holder nor the names of its contributors
       may be used to endorse or promote products derived from this software
       without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
    LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
    CONSEQUENTIAL DAMAGES.

    -----------------------------------------------------------------------
    PROVENANCE NOTICE

    This file is an independent clean-room reimplementation. No source code
    from uBlock Origin, AdGuard Scriptlets, Adblock Plus/eyeo snippets, or any
    other GPL/MPL-licensed adblock scriptlet project was viewed, copied, or
    otherwise used in creating this file. Scriptlet behavior implemented here
    is based solely on publicly known scriptlet naming conventions and
    standard Web/DOM/JavaScript APIs.
    -----------------------------------------------------------------------
*/

(function() {
// >>>> start of private namespace
'use strict';

/// abort-current-inline-script.js
/// alias acis.js
(function() {
    let propertyPath = '{{1}}';
    let sourceNeedle = '{{2}}';
    if ( /^\{\{\d+\}\}$/.test(propertyPath) || propertyPath === '' ) { return; }
    if ( /^\{\{\d+\}\}$/.test(sourceNeedle) ) { sourceNeedle = ''; }
    let sourcePattern;
    try {
        const match = sourceNeedle.match(/^\/(.*)\/([dgimsuvy]*)$/);
        sourcePattern = match ? new RegExp(match[1], match[2]) : new RegExp(sourceNeedle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    } catch (_) { return; }
    const abortMessage = `scriptlet-abort-${Math.random().toString(36).slice(2)}`;
    const previousOnError = window.onerror;
    window.onerror = function(message) {
        if ( String(message).includes(abortMessage) ) { return true; }
        if ( typeof previousOnError === 'function' ) { return previousOnError.apply(this, arguments); }
    };
    const shouldAbort = () => {
        const script = document.currentScript;
        sourcePattern.lastIndex = 0;
        return script instanceof HTMLScriptElement && !script.src && sourcePattern.test(script.textContent || '');
    };
    const install = (owner, parts) => {
        if ( owner == null || parts.length === 0 ) { return; }
        const key = parts[0];
        const descriptor = Object.getOwnPropertyDescriptor(owner, key);
        if ( descriptor && descriptor.configurable === false ) { return; }
        let value;
        try { value = descriptor && descriptor.get ? descriptor.get.call(owner) : owner[key]; } catch (_) { return; }
        if ( parts.length > 1 && value && (typeof value === 'object' || typeof value === 'function') ) {
            install(value, parts.slice(1));
        }
        Object.defineProperty(owner, key, {
            configurable: true,
            enumerable: descriptor ? descriptor.enumerable : true,
            get() {
                if ( parts.length === 1 && shouldAbort() ) { throw new ReferenceError(abortMessage); }
                return descriptor && descriptor.get ? descriptor.get.call(this) : value;
            },
            set(next) {
                if ( parts.length === 1 && shouldAbort() ) { throw new ReferenceError(abortMessage); }
                if ( descriptor && descriptor.set ) { descriptor.set.call(this, next); } else { value = next; }
                if ( parts.length > 1 && next && (typeof next === 'object' || typeof next === 'function') ) {
                    install(next, parts.slice(1));
                }
            },
        });
    };
    try { install(window, propertyPath.split('.').filter(Boolean)); } catch (_) {}
})();

/// abort-on-property-read.js
/// alias aopr.js
(function() {
    let propertyPath = '{{1}}';
    if ( /^\{\{\d+\}\}$/.test(propertyPath) || propertyPath === '' ) { return; }
    const abortMessage = `scriptlet-abort-${Math.random().toString(36).slice(2)}`;
    const previousOnError = window.onerror;
    window.onerror = function(message) {
        if ( String(message).includes(abortMessage) ) { return true; }
        if ( typeof previousOnError === 'function' ) { return previousOnError.apply(this, arguments); }
    };
    const install = (owner, parts) => {
        if ( owner == null || parts.length === 0 ) { return; }
        const key = parts[0];
        const descriptor = Object.getOwnPropertyDescriptor(owner, key);
        if ( descriptor && descriptor.configurable === false ) { return; }
        let value;
        try { value = descriptor && descriptor.get ? descriptor.get.call(owner) : owner[key]; } catch (_) { return; }
        if ( parts.length > 1 && value && (typeof value === 'object' || typeof value === 'function') ) {
            install(value, parts.slice(1));
        }
        Object.defineProperty(owner, key, {
            configurable: true,
            enumerable: descriptor ? descriptor.enumerable : true,
            get() {
                if ( parts.length === 1 ) { throw new ReferenceError(abortMessage); }
                return descriptor && descriptor.get ? descriptor.get.call(this) : value;
            },
            set(next) {
                if ( descriptor && descriptor.set ) { descriptor.set.call(this, next); } else { value = next; }
                if ( parts.length > 1 && next && (typeof next === 'object' || typeof next === 'function') ) {
                    install(next, parts.slice(1));
                }
            },
        });
    };
    try { install(window, propertyPath.split('.').filter(Boolean)); } catch (_) {}
})();

/// abort-on-property-write.js
/// alias aopw.js
(function() {
    let propertyPath = '{{1}}';
    if ( /^\{\{\d+\}\}$/.test(propertyPath) || propertyPath === '' ) { return; }
    const abortMessage = `scriptlet-abort-${Math.random().toString(36).slice(2)}`;
    const previousOnError = window.onerror;
    window.onerror = function(message) {
        if ( String(message).includes(abortMessage) ) { return true; }
        if ( typeof previousOnError === 'function' ) { return previousOnError.apply(this, arguments); }
    };
    const install = (owner, parts) => {
        if ( owner == null || parts.length === 0 ) { return; }
        const key = parts[0];
        const descriptor = Object.getOwnPropertyDescriptor(owner, key);
        if ( descriptor && descriptor.configurable === false ) { return; }
        let value;
        try { value = descriptor && descriptor.get ? descriptor.get.call(owner) : owner[key]; } catch (_) { return; }
        if ( parts.length > 1 && value && (typeof value === 'object' || typeof value === 'function') ) {
            install(value, parts.slice(1));
        }
        Object.defineProperty(owner, key, {
            configurable: true,
            enumerable: descriptor ? descriptor.enumerable : true,
            get() { return descriptor && descriptor.get ? descriptor.get.call(this) : value; },
            set(next) {
                if ( parts.length === 1 ) { throw new ReferenceError(abortMessage); }
                if ( descriptor && descriptor.set ) { descriptor.set.call(this, next); } else { value = next; }
                if ( next && (typeof next === 'object' || typeof next === 'function') ) { install(next, parts.slice(1)); }
            },
        });
    };
    try { install(window, propertyPath.split('.').filter(Boolean)); } catch (_) {}
})();

/// abort-on-stack-trace.js
/// alias aost.js
(function() {
    let propertyPath = '{{1}}';
    let stackNeedle = '{{2}}';
    if ( /^\{\{\d+\}\}$/.test(propertyPath) || propertyPath === '' ) { return; }
    if ( /^\{\{\d+\}\}$/.test(stackNeedle) || stackNeedle === '' ) { return; }
    let stackPattern;
    try {
        const match = stackNeedle.match(/^\/(.*)\/([dgimsuvy]*)$/);
        stackPattern = match ? new RegExp(match[1], match[2]) : new RegExp(stackNeedle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    } catch (_) { return; }
    const abortMessage = `scriptlet-abort-${Math.random().toString(36).slice(2)}`;
    const previousOnError = window.onerror;
    window.onerror = function(message) {
        if ( String(message).includes(abortMessage) ) { return true; }
        if ( typeof previousOnError === 'function' ) { return previousOnError.apply(this, arguments); }
    };
    const aborts = () => {
        stackPattern.lastIndex = 0;
        return stackPattern.test(new Error().stack || '');
    };
    const install = (owner, parts) => {
        if ( owner == null || parts.length === 0 ) { return; }
        const key = parts[0];
        const descriptor = Object.getOwnPropertyDescriptor(owner, key);
        if ( descriptor && descriptor.configurable === false ) { return; }
        let value;
        try { value = descriptor && descriptor.get ? descriptor.get.call(owner) : owner[key]; } catch (_) { return; }
        if ( parts.length > 1 && value && (typeof value === 'object' || typeof value === 'function') ) { install(value, parts.slice(1)); }
        Object.defineProperty(owner, key, {
            configurable: true,
            enumerable: descriptor ? descriptor.enumerable : true,
            get() {
                if ( parts.length === 1 && aborts() ) { throw new ReferenceError(abortMessage); }
                return descriptor && descriptor.get ? descriptor.get.call(this) : value;
            },
            set(next) {
                if ( parts.length === 1 && aborts() ) { throw new ReferenceError(abortMessage); }
                if ( descriptor && descriptor.set ) { descriptor.set.call(this, next); } else { value = next; }
                if ( parts.length > 1 && next && (typeof next === 'object' || typeof next === 'function') ) { install(next, parts.slice(1)); }
            },
        });
    };
    try { install(window, propertyPath.split('.').filter(Boolean)); } catch (_) {}
})();

/// addEventListener-defuser.js
/// alias aeld.js
(function() {
    let typeNeedle = '{{1}}';
    let listenerNeedle = '{{2}}';
    if ( /^\{\{\d+\}\}$/.test(typeNeedle) ) { typeNeedle = ''; }
    if ( /^\{\{\d+\}\}$/.test(listenerNeedle) ) { listenerNeedle = ''; }
    const compile = value => {
        if ( value === '' ) { return () => true; }
        let inverted = value.startsWith('!');
        if ( inverted ) { value = value.slice(1); }
        let pattern;
        try {
            const match = value.match(/^\/(.*)\/([dgimsuvy]*)$/);
            pattern = match ? new RegExp(match[1], match[2]) : new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
        } catch (_) { return () => false; }
        return input => { pattern.lastIndex = 0; return pattern.test(input) !== inverted; };
    };
    const matchesType = compile(typeNeedle);
    const matchesListener = compile(listenerNeedle);
    const original = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function(type, listener) {
        let source = '';
        try { source = String(listener); } catch (_) {}
        if ( matchesType(String(type)) && matchesListener(source) ) { return; }
        return original.apply(this, arguments);
    };
})();

/// addEventListener-logger.js
/// alias aell.js
(function() {
    const original = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function(type, listener) {
        let source = '';
        try { source = String(listener); } catch (_) {}
        console.log('[LOG] addEventListener("%s", %s)', String(type), source);
        return original.apply(this, arguments);
    };
})();

/// json-prune.js
(function() {
    let pruneText = '{{1}}';
    let requiredText = '{{2}}';
    if ( /^\{\{\d+\}\}$/.test(pruneText) || pruneText.trim() === '' ) { return; }
    if ( /^\{\{\d+\}\}$/.test(requiredText) ) { requiredText = ''; }
    const splitPaths = text => text.trim().split(/\s+/).filter(Boolean).map(path => path.split('.').filter(Boolean));
    const prunePaths = splitPaths(pruneText);
    const requiredPaths = splitPaths(requiredText);
    const hasPath = (value, parts) => {
        if ( parts.length === 0 ) { return true; }
        if ( value == null || (typeof value !== 'object' && typeof value !== 'function') ) { return false; }
        const [ key, ...rest ] = parts;
        if ( key === '*' || key === '[]' ) { return Object.values(value).some(child => hasPath(child, rest)); }
        return Object.prototype.hasOwnProperty.call(value, key) && hasPath(value[key], rest);
    };
    const removePath = (value, parts) => {
        if ( value == null || typeof value !== 'object' || parts.length === 0 ) { return; }
        const [ key, ...rest ] = parts;
        if ( key === '*' || key === '[]' ) {
            for ( const childKey of Object.keys(value) ) {
                if ( rest.length === 0 ) { delete value[childKey]; } else { removePath(value[childKey], rest); }
            }
        } else if ( rest.length === 0 ) {
            delete value[key];
        } else {
            removePath(value[key], rest);
        }
    };
    const original = JSON.parse;
    JSON.parse = function() {
        const value = original.apply(this, arguments);
        try {
            if ( requiredPaths.every(path => hasPath(value, path)) ) {
                for ( const path of prunePaths ) { removePath(value, path); }
            }
        } catch (_) {}
        return value;
    };
})();

/// nano-setInterval-booster.js
/// alias nano-sib.js
(function() {
    let callbackNeedle = '{{1}}';
    let delayText = '{{2}}';
    let factorText = '{{3}}';
    if ( /^\{\{\d+\}\}$/.test(callbackNeedle) ) { callbackNeedle = ''; }
    const targetDelay = Number(delayText);
    const factor = Number(factorText);
    if ( !Number.isFinite(targetDelay) || !Number.isFinite(factor) || factor < 0 ) { return; }
    const original = window.setInterval;
    window.setInterval = function(callback, delay) {
        let source = '';
        try { source = String(callback); } catch (_) {}
        const adjusted = source.includes(callbackNeedle) && Number(delay) === targetDelay ? targetDelay * factor : delay;
        const args = Array.from(arguments);
        args[1] = adjusted;
        return original.apply(this, args);
    };
})();

/// nano-setTimeout-booster.js
/// alias nano-stb.js
(function() {
    let callbackNeedle = '{{1}}';
    let delayText = '{{2}}';
    let factorText = '{{3}}';
    if ( /^\{\{\d+\}\}$/.test(callbackNeedle) ) { callbackNeedle = ''; }
    const targetDelay = Number(delayText);
    const factor = Number(factorText);
    if ( !Number.isFinite(targetDelay) || !Number.isFinite(factor) || factor < 0 ) { return; }
    const original = window.setTimeout;
    window.setTimeout = function(callback, delay) {
        let source = '';
        try { source = String(callback); } catch (_) {}
        const adjusted = source.includes(callbackNeedle) && Number(delay) === targetDelay ? targetDelay * factor : delay;
        const args = Array.from(arguments);
        args[1] = adjusted;
        return original.apply(this, args);
    };
})();

/// noeval-if.js
(function() {
    let needle = '{{1}}';
    if ( /^\{\{\d+\}\}$/.test(needle) ) { needle = ''; }
    let pattern;
    try {
        const match = needle.match(/^\/(.*)\/([dgimsuvy]*)$/);
        pattern = match ? new RegExp(match[1], match[2]) : new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    } catch (_) { return; }
    const original = window.eval;
    window.eval = function(source) {
        pattern.lastIndex = 0;
        if ( pattern.test(String(source)) ) { return; }
        return original.apply(this, arguments);
    };
})();

/// remove-attr.js
/// alias ra.js
(function() {
    let attributeText = '{{1}}';
    let selector = '{{2}}';
    if ( /^\{\{\d+\}\}$/.test(attributeText) || attributeText === '' ) { return; }
    const attributes = attributeText.split('|').map(value => value.trim()).filter(Boolean);
    if ( /^\{\{\d+\}\}$/.test(selector) || selector === '' ) { selector = attributes.map(name => `[${CSS.escape(name)}]`).join(','); }
    if ( selector === '' ) { return; }
    const apply = () => {
        try {
            for ( const node of document.querySelectorAll(selector) ) {
                for ( const name of attributes ) { node.removeAttribute(name); }
            }
        } catch (_) {}
    };
    const start = () => {
        apply();
        try { new MutationObserver(apply).observe(document, { childList: true, subtree: true, attributes: true }); } catch (_) {}
    };
    if ( document.readyState === 'loading' ) { document.addEventListener('DOMContentLoaded', start, { once: true }); } else { start(); }
})();

/// remove-class.js
/// alias rc.js
(function() {
    let classText = '{{1}}';
    let selector = '{{2}}';
    if ( /^\{\{\d+\}\}$/.test(classText) || classText === '' ) { return; }
    const classes = classText.split('|').map(value => value.trim()).filter(Boolean);
    if ( /^\{\{\d+\}\}$/.test(selector) || selector === '' ) { selector = classes.map(name => `.${CSS.escape(name)}`).join(','); }
    if ( selector === '' ) { return; }
    const apply = () => {
        try {
            for ( const node of document.querySelectorAll(selector) ) {
                if ( classes.some(name => node.classList.contains(name)) ) { node.classList.remove(...classes); }
            }
        } catch (_) {}
    };
    const start = () => {
        apply();
        try { new MutationObserver(apply).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: [ 'class' ] }); } catch (_) {}
    };
    if ( document.readyState === 'loading' ) { document.addEventListener('DOMContentLoaded', start, { once: true }); } else { start(); }
})();

/// requestAnimationFrame-if.js
/// alias raf-if.js
(function() {
    let needle = '{{1}}';
    if ( /^\{\{\d+\}\}$/.test(needle) ) { needle = ''; }
    const negated = needle.startsWith('!');
    if ( negated ) { needle = needle.slice(1); }
    let pattern;
    try {
        const match = needle.match(/^\/(.*)\/([dgimsuvy]*)$/);
        pattern = match ? new RegExp(match[1], match[2]) : new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    } catch (_) { return; }
    const original = window.requestAnimationFrame;
    if ( typeof original !== 'function' ) { return; }
    window.requestAnimationFrame = function(callback) {
        let source = '';
        try { source = String(callback); } catch (_) {}
        pattern.lastIndex = 0;
        const matched = pattern.test(source);
        return original.call(this, (negated ? matched : !matched) ? function() {} : callback);
    };
})();

/// no-requestAnimationFrame-if.js
/// alias norafif.js
(function() {
    let needle = '{{1}}';
    if ( /^\{\{\d+\}\}$/.test(needle) ) { needle = ''; }
    let inverted = needle.startsWith('!');
    if ( inverted ) { needle = needle.slice(1); }
    let pattern;
    try {
        const match = needle.match(/^\/(.*)\/([dgimsuvy]*)$/);
        pattern = match ? new RegExp(match[1], match[2]) : new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    } catch (_) { return; }
    const original = window.requestAnimationFrame;
    if ( typeof original !== 'function' ) { return; }
    window.requestAnimationFrame = function(callback) {
        let source = '';
        try { source = String(callback); } catch (_) {}
        pattern.lastIndex = 0;
        const blocked = pattern.test(source) !== inverted;
        return original.call(this, blocked ? function() {} : callback);
    };
})();

/// set-constant.js
/// alias set.js
(function() {
    let propertyPath = '{{1}}';
    let valueText = '{{2}}';
    if ( /^\{\{\d+\}\}$/.test(propertyPath) || propertyPath === '' ) { return; }
    if ( /^\{\{\d+\}\}$/.test(valueText) ) { valueText = 'undefined'; }
    let constant;
    if ( valueText === 'undefined' ) { constant = undefined; }
    else if ( valueText === 'null' ) { constant = null; }
    else if ( valueText === 'true' ) { constant = true; }
    else if ( valueText === 'false' ) { constant = false; }
    else if ( valueText === 'noopFunc' || valueText === 'noopFn' ) { constant = function() {}; }
    else if ( valueText === 'trueFunc' ) { constant = function() { return true; }; }
    else if ( valueText === 'falseFunc' ) { constant = function() { return false; }; }
    else if ( valueText !== '' && Number.isFinite(Number(valueText)) ) { constant = Number(valueText); }
    else { constant = valueText; }
    const install = (owner, parts) => {
        if ( owner == null || parts.length === 0 ) { return; }
        const key = parts[0];
        const descriptor = Object.getOwnPropertyDescriptor(owner, key);
        if ( descriptor && descriptor.configurable === false ) { return; }
        let value;
        try { value = descriptor && descriptor.get ? descriptor.get.call(owner) : owner[key]; } catch (_) { return; }
        if ( parts.length > 1 ) {
            if ( value && (typeof value === 'object' || typeof value === 'function') ) { install(value, parts.slice(1)); }
            Object.defineProperty(owner, key, {
                configurable: true,
                enumerable: descriptor ? descriptor.enumerable : true,
                get() { return descriptor && descriptor.get ? descriptor.get.call(this) : value; },
                set(next) {
                    if ( descriptor && descriptor.set ) { descriptor.set.call(this, next); } else { value = next; }
                    if ( next && (typeof next === 'object' || typeof next === 'function') ) { install(next, parts.slice(1)); }
                },
            });
            return;
        }
        let active = true;
        Object.defineProperty(owner, key, {
            configurable: true,
            enumerable: descriptor ? descriptor.enumerable : true,
            get() { return active ? constant : value; },
            set(next) {
                if ( active && next !== null && constant !== null && typeof next !== typeof constant ) { active = false; value = next; }
            },
        });
    };
    try { install(window, propertyPath.split('.').filter(Boolean)); } catch (_) {}
})();

/// setInterval-defuser.js
/// alias sid.js
(function() {
    let callbackNeedle = '{{1}}';
    let delayText = '{{2}}';
    if ( /^\{\{\d+\}\}$/.test(callbackNeedle) ) { callbackNeedle = ''; }
    const targetDelay = /^\{\{\d+\}\}$/.test(delayText) || delayText === '' ? null : Number(delayText);
    const original = window.setInterval;
    window.setInterval = function(callback, delay) {
        let source = '';
        try { source = String(callback); } catch (_) {}
        const blocked = source.includes(callbackNeedle) && (targetDelay === null || Number(delay) === targetDelay);
        const args = Array.from(arguments);
        if ( blocked ) { args[0] = function() {}; }
        return original.apply(this, args);
    };
})();

/// no-setInterval-if.js
/// alias nosiif.js
(function() {
    let callbackNeedle = '{{1}}';
    let delayText = '{{2}}';
    if ( /^\{\{\d+\}\}$/.test(callbackNeedle) ) { callbackNeedle = ''; }
    const targetDelay = /^\{\{\d+\}\}$/.test(delayText) || delayText === '' ? null : Number(delayText);
    const original = window.setInterval;
    window.setInterval = function(callback, delay) {
        let source = '';
        try { source = String(callback); } catch (_) {}
        const blocked = source.includes(callbackNeedle) && (targetDelay === null || Number(delay) === targetDelay);
        const args = Array.from(arguments);
        if ( blocked ) { args[0] = function() {}; }
        return original.apply(this, args);
    };
})();

/// setTimeout-defuser.js
/// alias std.js
(function() {
    let callbackNeedle = '{{1}}';
    let delayText = '{{2}}';
    if ( /^\{\{\d+\}\}$/.test(callbackNeedle) ) { callbackNeedle = ''; }
    const targetDelay = /^\{\{\d+\}\}$/.test(delayText) || delayText === '' ? null : Number(delayText);
    const original = window.setTimeout;
    window.setTimeout = function(callback, delay) {
        let source = '';
        try { source = String(callback); } catch (_) {}
        const blocked = source.includes(callbackNeedle) && (targetDelay === null || Number(delay) === targetDelay);
        const args = Array.from(arguments);
        if ( blocked ) { args[0] = function() {}; }
        return original.apply(this, args);
    };
})();

/// no-setTimeout-if.js
/// alias nostif.js
(function() {
    let callbackNeedle = '{{1}}';
    let delayText = '{{2}}';
    if ( /^\{\{\d+\}\}$/.test(callbackNeedle) ) { callbackNeedle = ''; }
    const targetDelay = /^\{\{\d+\}\}$/.test(delayText) || delayText === '' ? null : Number(delayText);
    const original = window.setTimeout;
    window.setTimeout = function(callback, delay) {
        let source = '';
        try { source = String(callback); } catch (_) {}
        const blocked = source.includes(callbackNeedle) && (targetDelay === null || Number(delay) === targetDelay);
        const args = Array.from(arguments);
        if ( blocked ) { args[0] = function() {}; }
        return original.apply(this, args);
    };
})();

/// webrtc-if.js
(function() {
    let allowedNeedle = '{{1}}';
    if ( /^\{\{\d+\}\}$/.test(allowedNeedle) ) { allowedNeedle = ''; }
    let pattern;
    try {
        const match = allowedNeedle.match(/^\/(.*)\/([dgimsuvy]*)$/);
        pattern = match ? new RegExp(match[1], match[2]) : new RegExp(allowedNeedle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    } catch (_) { return; }
    for ( const name of [ 'RTCPeerConnection', 'webkitRTCPeerConnection' ] ) {
        const Original = window[name];
        if ( typeof Original !== 'function' ) { continue; }
        const Wrapped = function(configuration) {
            let allowed = false;
            try {
                const servers = Array.isArray(configuration && configuration.iceServers) ? configuration.iceServers : [];
                allowed = servers.some(server => {
                    const urls = server && (server.urls || server.url);
                    return (Array.isArray(urls) ? urls : [ urls ]).some(url => {
                        pattern.lastIndex = 0;
                        return pattern.test(String(url || ''));
                    });
                });
            } catch (_) {}
            const args = allowed ? Array.from(arguments) : [];
            return Reflect.construct(Original, args, new.target || Original);
        };
        Wrapped.prototype = Original.prototype;
        try { Object.setPrototypeOf(Wrapped, Original); } catch (_) {}
        window[name] = Wrapped;
    }
})();

/// window.name-defuser.js
(function() {
    if ( window === window.top ) { window.name = ''; }
})();

/// overlay-buster.js
(function() {
    const scan = () => {
        try {
            const rootStyle = getComputedStyle(document.documentElement);
            const bodyStyle = document.body && getComputedStyle(document.body);
            if ( rootStyle.overflow === 'hidden' ) { document.documentElement.style.setProperty('overflow', 'auto', 'important'); }
            if ( bodyStyle && bodyStyle.overflow === 'hidden' ) { document.body.style.setProperty('overflow', 'auto', 'important'); }
            for ( const element of document.body ? document.body.querySelectorAll('*') : [] ) {
                const style = getComputedStyle(element);
                if ( style.position !== 'fixed' ) { continue; }
                const rect = element.getBoundingClientRect();
                if ( rect.width >= innerWidth * 0.9 && rect.height >= innerHeight * 0.9 ) { element.remove(); }
            }
        } catch (_) {}
    };
    const start = () => { window.setTimeout(scan, 0); };
    if ( document.readyState === 'loading' ) { document.addEventListener('DOMContentLoaded', start, { once: true }); } else { start(); }
})();

/// alert-buster.js
(function() {
    window.alert = function(message) { console.info(message); };
})();

/// gpt-defuser.js
(function() {
    const noop = function() {};
    for ( const name of [ 'resetGPT', 'setupGPT' ] ) {
        try {
            Object.defineProperty(window, name, {
                configurable: false,
                enumerable: true,
                get() { return noop; },
                set() {},
            });
        } catch (_) { window[name] = noop; }
    }
})();

/// nowebrtc.js
(function() {
    const createChannel = () => ({
        readyState: 'open',
        send() {},
        close() {},
        addEventListener() {},
        removeEventListener() {},
    });
    const disable = name => {
        const Original = window[name];
        if ( typeof Original !== 'function' ) { return; }
        try { Original.prototype.createDataChannel = createChannel; } catch (_) {}
        const Stub = function(configuration) {
            console.log('WebRTC connection blocked', configuration);
        };
        Stub.prototype.createDataChannel = createChannel;
        Stub.prototype.createOffer = function() {};
        Stub.prototype.createAnswer = function() {};
        Stub.prototype.setLocalDescription = function() {};
        Stub.prototype.setRemoteDescription = function() {};
        Stub.prototype.addIceCandidate = function() {};
        Stub.prototype.close = function() {};
        Stub.prototype.toString = () => '[object RTCPeerConnection]';
        window[name] = Stub;
    };
    disable('RTCPeerConnection');
    disable('webkitRTCPeerConnection');
})();

/// golem.de.js
(function() {
    const original = window.addEventListener;
    window.addEventListener = function(type, handler) {
        const result = original.apply(this, arguments);
        if ( type === 'load' && typeof handler === 'function' && /clearTimeout\s*\(/.test(String(handler)) ) {
            try { handler.call(this, new Event('load')); } catch (_) {}
        }
        return result;
    };
})();

/// upmanager-defuser.js
(function() {
    const previousOnError = window.onerror;
    window.onerror = function(message) {
        if ( /upManager/i.test(String(message)) ) { return true; }
        if ( typeof previousOnError === 'function' ) { return previousOnError.apply(this, arguments); }
    };
    Object.defineProperty(window, 'upManager', {
        configurable: false,
        enumerable: true,
        value: function() {},
        writable: false,
    });
})();

/// smartadserver.com.js
(function() {
    const noop = function() {};
    const smartAd = Object.freeze({
        LoadAds: noop,
        Register: noop,
    });
    Object.defineProperties(window, {
        SmartAdObject: { configurable: false, value: noop, writable: false },
        SmartAdServerAjax: { configurable: false, value: noop, writable: false },
        smartAd: { configurable: false, value: smartAd, writable: false },
    });
})();

/// adfly-defuser.js
(function() {
    let value;
    const decode = token => {
        if ( typeof token !== 'string' || token === '' ) { return; }
        let left = '';
        let right = '';
        for ( let i = 0; i < token.length; i++ ) {
            if ( i % 2 === 0 ) { left += token[i]; } else { right = token[i] + right; }
        }
        const data = (left + right).split('');
        for ( let i = 0; i < data.length; i++ ) {
            if ( !/^\d$/.test(data[i]) ) { continue; }
            for ( let j = i + 1; j < data.length; j++ ) {
                if ( !/^\d$/.test(data[j]) ) { continue; }
                const digit = Number(data[i]) ^ Number(data[j]);
                if ( digit < 10 ) { data[i] = String(digit); }
                i = j;
                break;
            }
        }
        let decoded;
        try { decoded = atob(data.join('')); } catch (_) { return; }
        const prefix = '0123456789abcdef';
        const suffix = 'fedcba9876543210';
        if ( !decoded.startsWith(prefix) || !decoded.endsWith(suffix) ) { return; }
        let url;
        try { url = new URL(decoded.slice(prefix.length, -suffix.length), location.href); } catch (_) { return; }
        if ( url.protocol !== 'http:' && url.protocol !== 'https:' ) { return; }
        return url.href;
    };
    try {
        Object.defineProperty(window, 'ysmm', {
            configurable: false,
            enumerable: true,
            get() { return value; },
            set(next) {
                value = next;
                const url = decode(next);
                if ( url === undefined ) { return; }
                if ( typeof window.stop === 'function' ) { window.stop(); }
                window.onbeforeunload = null;
                window.location.href = url;
            },
        });
    } catch (_) {}
})();

/// disable-newtab-links.js
(function() {
    document.addEventListener('click', event => {
        let link;
        try { link = event.target instanceof Element ? event.target.closest('a[target="_blank"]') : null; } catch (_) { return; }
        if ( link ) { event.preventDefault(); }
    }, true);
})();

/// damoh-defuser.js
(function() {
    const restore = () => {
        const currentDocument = window.document;
        if ( !currentDocument ) { return; }
        for ( const video of currentDocument.querySelectorAll('video') ) {
            const source = video.querySelector('meta[itemprop="contentURL"]');
            if ( !source || !source.content ) { continue; }
            const thumbnail = video.querySelector('meta[itemprop="thumbnailUrl"]');
            try { video.pause(); } catch (_) {}
            video.controls = true;
            video.src = source.content;
            if ( thumbnail && thumbnail.content ) { video.poster = thumbnail.content; }
        }
    };
    const schedule = () => {
        if ( typeof requestAnimationFrame === 'function' ) { requestAnimationFrame(restore); } else { restore(); }
    };
    try { new MutationObserver(schedule).observe(document, { childList: true, subtree: true }); } catch (_) {}
})();

/// twitch-videoad.js
(function() {
    const original = window.fetch;
    if ( typeof original !== 'function' ) { return; }
    window.fetch = function(input) {
        let replacement = input;
        try {
            const isRequest = typeof window.Request === 'function' && input instanceof window.Request;
            const raw = isRequest ? input.url : String(input);
            const url = new URL(raw, location.href);
            if ( /\/access_token\/?$/.test(url.pathname) && url.searchParams.has('platform') ) {
                url.searchParams.set('platform', '_');
                replacement = isRequest ? new window.Request(url.href, input) : url.href;
            }
        } catch (_) {}
        const args = Array.from(arguments);
        args[0] = replacement;
        return original.apply(this, args);
    };
})();

/// fingerprint2.js
(function() {
    const identifier = Array.from({ length: 32 }, () => Math.floor(Math.random() * 16).toString(16)).join('');
    const get = callback => {
        if ( typeof callback !== 'function' ) { return; }
        Promise.resolve().then(() => callback(identifier, []));
    };
    window.Fingerprint2 = function() {};
    window.Fingerprint2.get = get;
    window.Fingerprint2.prototype.get = get;
})();

/// cookie-remover.js
(function() {
    let nameNeedle = '{{1}}';
    if ( /^\{\{\d+\}\}$/.test(nameNeedle) || nameNeedle === '' ) { return; }
    let pattern;
    try {
        const match = nameNeedle.match(/^\/(.*)\/([dgimsuvy]*)$/);
        pattern = match ? new RegExp(match[1], match[2]) : new RegExp(`^${nameNeedle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`);
    } catch (_) { return; }
    try {
        for ( const pair of document.cookie.split(';') ) {
            const name = pair.split('=')[0].trim();
            pattern.lastIndex = 0;
            if ( !pattern.test(name) ) { continue; }
            const expiry = `${encodeURIComponent(name)}=; expires=Thu, 01 Jan 1970 00:00:00 GMT`;
            document.cookie = `${expiry}; path=/`;
            document.cookie = expiry;
        }
    } catch (_) {}
})();

// These lines below are skipped by the resource parser.
// <<<< end of private namespace
})();
