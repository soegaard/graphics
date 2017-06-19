#lang typed/racket/base

(provide (all-defined-out))

(require "../draw.rkt")
(require "font.rkt")
(require "source.rkt")
(require "require.rkt")

(module unsafe racket/base
  (provide (all-defined-out))
  
  (require "pangocairo.rkt")
  (require "paint.rkt")
  (require (submod "font.rkt" unsafe))
  
  (define (λbitmap width height density λargb)
    (define-values (img cr w h) (make-cairo-image width height density))
    (define surface (cairo_get_target cr))
    (define buffer (cairo_image_surface_get_data surface))
    (define stride (cairo_image_surface_get_stride surface))
    (define total (unsafe-bytes-length buffer))
    (define W (unsafe-fxquotient stride 4))
    (define H (unsafe-fxquotient total stride))
    (let y-loop ([y 0])
      (when (unsafe-fx< y H)
        (let x-loop ([x 0] [idx (unsafe-fx* y stride)])
          (when (unsafe-fx< x W)
            (define-values (a r g b) (λargb x y W H))
            (unsafe-bytes-set! buffer (unsafe-fx+ idx A) (argb->datum a))
            (unsafe-bytes-set! buffer (unsafe-fx+ idx R) (argb->datum r))
            (unsafe-bytes-set! buffer (unsafe-fx+ idx G) (argb->datum g))
            (unsafe-bytes-set! buffer (unsafe-fx+ idx B) (argb->datum b))
            (x-loop (unsafe-fx+ x 1) (unsafe-fx+ idx 4))))
        (y-loop (unsafe-fx+ y 1))))
    (cairo_destroy cr)
    img)
  
  (define (bitmap_blank width height density)
    (define-values (img cr w h) (make-cairo-image width height density))
    (cairo_destroy cr)
    img)

  (define (bitmap_pattern width height background density)
    (define-values (img cr w h) (make-cairo-image* width height background density))
    (cairo_destroy cr)
    img)

  (define (bitmap_arc radius start end border background density)
    (define fllength (unsafe-fl* radius 2.0))
    (define-values (img cr w h) (make-cairo-image fllength fllength density))
    (define line-width (if (struct? border) (unsafe-struct-ref border 1) 0.0))
    (cairo_translate cr radius radius)
    (cairo_arc cr 0.0 0.0 (unsafe-fl- radius (unsafe-fl/ line-width 2.0)) start end)
    (cairo-render cr border background)
    (cairo_destroy cr)
    img)

  (define (bitmap_elliptical_arc width height start end border background density)
    (define radius (unsafe-fl/ width 2.0))
    (define-values (img cr w h) (make-cairo-image width height density))
    (define line-width (if (struct? border) (unsafe-struct-ref border 1) 0.0))
    (cairo_translate cr radius (unsafe-fl/ height 2.0))
    (cairo_scale cr 1.0 (unsafe-fl/ height width))
    (cairo_arc cr 0.0 0.0 (unsafe-fl- radius (unsafe-fl/ line-width 2.0)) start end)
    (cairo-render cr border background)
    (cairo_destroy cr)
    img)
  
  (define (bitmap_rectangle flwidth flheight border background density)
    (define-values (img cr w h) (make-cairo-image flwidth flheight density))
    (define line-width (if (struct? border) (unsafe-struct-ref border 1) 0.0))
    (define inset (unsafe-fl/ line-width 2.0))
    (cairo_rectangle cr inset inset (unsafe-fl- flwidth line-width) (unsafe-fl- flheight line-width))
    (cairo-render cr border background)
    (cairo_destroy cr)
    img)

  (define (bitmap_rounded_rectangle flwidth flheight radius border background density)
    (define-values (img cr w h) (make-cairo-image flwidth flheight density))
    (define line-width (if (struct? border) (unsafe-struct-ref border 1) 0.0))
    (define inset (unsafe-fl/ line-width 2.0))
    (define flradius
      (let ([short (unsafe-flmin flwidth flheight)])
        (unsafe-flmin (unsafe-fl/ short 2.0) (radius-normalize radius short))))
    (define tlset (unsafe-fl+ inset flradius))
    (define xrset (unsafe-fl- (unsafe-fl- flwidth inset) flradius))
    (define ybset (unsafe-fl- (unsafe-fl- flheight inset) flradius))
    (cairo_new_sub_path cr) ; not neccessary
    (cairo_arc cr xrset tlset flradius -pi/2 0.0)
    (cairo_arc cr xrset ybset flradius 0.0   pi/2)
    (cairo_arc cr tlset ybset flradius pi/2  pi)
    (cairo_arc cr tlset tlset flradius pi    3pi/2)
    (cairo_close_path cr)
    (cairo-render cr border background)
    (cairo_destroy cr)
    img)

  (define (bitmap_stadium fllength radius border background density)
    (define flradius (radius-normalize radius fllength))
    (define flheight (unsafe-fl* flradius 2.0))
    (define flwidth (unsafe-fl+ fllength flheight))
    (define-values (img cr w h) (make-cairo-image flwidth flheight density))
    (define line-width (if (struct? border) (unsafe-struct-ref border 1) 0.0))
    (define inset-radius (unsafe-fl- flradius (unsafe-fl/ line-width 2.0)))
    (cairo_new_sub_path cr) ; not neccessary
    (cairo_arc_negative cr flradius                       flradius inset-radius -pi/2 pi/2)
    (cairo_arc_negative cr (unsafe-fl+ flradius fllength) flradius inset-radius pi/2  3pi/2)
    (cairo_close_path cr)
    (cairo-render cr border background)
    (cairo_destroy cr)
    img)
  
  (define (bitmap_paragraph words max-width max-height indent spacing wrap ellipsize font-desc lines fgsource bgsource density)
    (define layout (bitmap_create_layout the-cairo max-width max-height indent spacing wrap ellipsize))
    (pango_layout_set_font_description layout font-desc)
    (pango_layout_set_text layout words)

    (when (pair? lines)
      (define attrs (pango_attr_list_new))
      (when (memq 'line-through lines) (pango_attr_list_insert attrs (pango_attr_strikethrough_new #true)))
      (cond [(memq 'undercurl lines) (pango_attr_list_insert attrs (pango_attr_underline_new PANGO_UNDERLINE_ERROR))]
            [(memq 'underdouble lines) (pango_attr_list_insert attrs (pango_attr_underline_new PANGO_UNDERLINE_DOUBLE))]
            [(memq 'underline lines) (pango_attr_list_insert attrs (pango_attr_underline_new PANGO_UNDERLINE_SINGLE))])
      (pango_layout_set_attributes layout attrs)
      (pango_attr_list_unref attrs))

    (define-values (pango-width pango-height) (pango_layout_get_size layout))
    (define-values (flwidth flheight) (values (~metric pango-width) (unsafe-flmin (~metric pango-height) max-height)))
    (define-values (bmp cr draw-text?)
      (if (unsafe-fl<= flwidth max-width)
          (let-values ([(bmp cr w h) (make-cairo-image* flwidth flheight bgsource density)])
            (values bmp cr #true))
          (let-values ([(w h) (and (pango_layout_set_text layout " ") (pango_layout_get_size layout))])
            (define draw-text? (unsafe-fl>= max-width (~metric w)))
            (define smart-height (if draw-text? flheight (unsafe-flmin (~metric h) flheight)))
            (define-values (bmp cr _w _h) (make-cairo-image* max-width smart-height bgsource density))
            (values bmp cr draw-text?))))
    (when draw-text?
      (cairo-set-source cr fgsource)
      (cairo_move_to cr 0 0)
      (pango_cairo_show_layout cr layout))
    (cairo_destroy cr)
    bmp)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (define-values (-pi/2 pi/2 3pi/2 2pi) (values (~radian -90.0) (~radian 90.0) (~radian 270.0) (unsafe-fl* pi 2.0)))
  
  (define (argb->datum v)
    (unsafe-fxmin
     (unsafe-fxmax
      (unsafe-fl->fx
       (unsafe-fl* (real->double-flonum v) 255.0))
      #x00)
     #xFF))

  (define (radius-normalize radius 100%)
    (define flradius (real->double-flonum radius))
    (if (single-flonum? radius) (unsafe-fl* flradius 100%) flradius))
  
  (define (bitmap_create_layout cr max-width max-height indent spacing wrap-mode ellipsize-mode)
    (define context (the-context))
    (define layout (pango_layout_new context))
    (pango_layout_set_width layout (if (flonum? max-width) (~size max-width) max-width))
    (pango_layout_set_height layout (if (flonum? max-height) (~size max-height) max-height))
    (pango_layout_set_indent layout (~size indent))   ; (~size nan.0) == (~size inf.0) == 0
    (pango_layout_set_spacing layout (~size spacing)) ; pango knows the minimum spacing
    (pango_layout_set_wrap layout wrap-mode)
    (pango_layout_set_ellipsize layout ellipsize-mode)
    layout)

  (define the-context
    (let ([&context (box #false)])
      (lambda []
        (or (unbox &context)
            (let ([fontmap (pango_cairo_font_map_get_default)])
              (define context (pango_font_map_create_context fontmap))
              (define options (cairo_font_options_create))
              (cairo_font_options_set_antialias options CAIRO_ANTIALIAS_DEFAULT)
              (pango_cairo_context_set_font_options context options)
              (set-box! &context context)
              (unbox &context)))))))

(define-type XYWH->ARGB (-> Nonnegative-Fixnum Nonnegative-Fixnum Positive-Fixnum Positive-Fixnum (Values Real Real Real Real)))

(unsafe/require/provide
 (submod "." unsafe)
 [λbitmap (-> Flonum Flonum Flonum XYWH->ARGB Bitmap)]
 [bitmap_blank (-> Flonum Flonum Flonum Bitmap)]
 [bitmap_pattern (-> Flonum Flonum Bitmap-Source Flonum Bitmap)]
 [bitmap_arc (-> Flonum Real Real (Option Paint) (Option Bitmap-Source) Flonum Bitmap)]
 [bitmap_elliptical_arc (-> Flonum Flonum Real Real (Option Paint) (Option Bitmap-Source) Flonum Bitmap)]
 [bitmap_rectangle (-> Flonum Flonum (Option Paint) (Option Bitmap-Source) Flonum Bitmap)]
 [bitmap_rounded_rectangle (-> Flonum Flonum Real (Option Paint) (Option Bitmap-Source) Flonum Bitmap)]
 [bitmap_stadium (-> Flonum Real (Option Paint) (Option Bitmap-Source) Flonum Bitmap)]
 [bitmap_paragraph (-> String (U Integer Flonum) (U Integer Flonum) Flonum Flonum Integer Integer Font-Description (Listof Symbol)
                       Bitmap-Source Bitmap-Source Flonum Bitmap)])