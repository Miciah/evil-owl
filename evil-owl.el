;;; evil-owl.el --- posframe preview for evil's register and mark commands -*- lexical-binding: t -*-

;; Copyright (C) 2019 Daniel Phan

;; Author: Daniel Phan <daniel.phan36@gmail.com>
;; Version: 0.0.1
;; Package-Requires: ((emacs "26.1") (evil "1.2.13") (posframe "0.5.0"))
;; Homepage: https://github.com/mamapanda/evil-owl
;; Keywords: emulations, evil, visual

;; This file is NOT part of GNU Emacs.

;;; License:
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; TODO: commentary section

;;; Code:

;; TODO: sometimes, the buffer focus changes when using evil-owl commands
;;       can't figure out an exact case, but it often happens with mark commands
;;       do something in the current buffer, switch to another, then use m
;;     seems that `evil-get-marker' doesn't properly switch the buffer back
;;       - i think the culprits are the ` and ' marks

;; TODO: interesting comment about the '. mark
;;    https://github.com/Andrew-William-Smith/evil-fringe-mark/blob/master/evil-fringe-mark.el#L284

;; * Setup
(require 'cl-lib)
(require 'evil)
(require 'posframe)

(defgroup evil-owl nil
  "Register and mark preview popups."
  :prefix 'evil-owl
  :group 'evil)

;; * User Options
;; ** Variables
;; TODO: we don't actually need the -alist suffix, do we?
(defcustom evil-owl-register-group-alist
  `(("Named"     . ,(cl-loop for c from ?a to ?z collect c))
    ("Numbered"  . ,(cl-loop for c from ?0 to ?9 collect c))
    ("Special"   . (?\" ?* ?+ ?-))
    ("Read-only" . (?% ?# ?/ ?: ?.)))
  "An alist of register group names to registers.
Groups and registers will be displayed in the same order they appear
in this variable."
  :type '(alist :key string :value (repeat character)))

(defcustom evil-owl-mark-group-alist
  `(("Named Local" . ,(cl-loop for c from ?a to ?z collect c))
    ("Named Global" . ,(cl-loop for c from ?A to ?Z collect c))
    ("Numbered" . ,(cl-loop for c from ?0 to ?9 collect c))
    ;; `evil-get-marker' currently bugs out with the last jump marks.
    ;; If they're in a different buffer, `evil-get-marker' will switch
    ;; to that buffer and leave it open.
    ("Special" . (?[ ?] ?< ?> ?^ ?. ?( ?) ?{ ?})))
  "" ; TODO: docstring
  :type '(alist :key string :value (repeat character)))

(defcustom evil-owl-header-format "%s"
  "Format for group headers.
An empty string means to not show a header."
  :type 'string)

(defcustom evil-owl-register-format "%r: %s"
  "Format for register entries.
Possible format specifiers are:
- %r: the register
- %s: the register's contents"
  :type 'string)

(defcustom evil-owl-local-mark-format "%m: [l: %-5l, c: %-5c]"
  "Format for local mark entries.
Possible format specifiers are:
- %m: the mark
- %l: the mark's line number
- %c: the mark's column number
- %b: the mark's buffer"
  :type 'string)

(defcustom evil-owl-global-mark-format "%m: [l: %-5l, c: %-5c] %b"
  "Format for global mark entries.
Possible format specifiers are:
- %m: the mark
- %l: the mark's line number
- %c: the mark's column number
- %b: the mark's buffer"
  :type 'string)

(defcustom evil-owl-separator "\n"
  "The separator string to place between sections."
  :type 'string)

(defcustom evil-owl-extra-posframe-args nil
  "Extra arguments to pass to `posframe-show'."
  :type 'list)

(defcustom evil-owl-idle-delay 1
  "The idle delay, in seconds, before the popup appears."
  :type 'float)

(defcustom evil-owl-register-char-limit nil
  "Maximum number of characters to consider in a string register."
  :type 'integer)

(defcustom evil-owl-lighter " owl"
  "Lighter for `evil-owl-mode'."
  :type 'string)

;; ** Faces
(defface evil-owl-group-name '((t (:inherit font-lock-function-name-face)))
  "The face for group names.")

(defface evil-owl-entry-name '((t (:inherit font-lock-type-face)))
  "The face for marks and registers.")

;; * Display Strings
;; ** Common
(defun evil-owl--header-string (group-name)
  (if (string-empty-p evil-owl-header-format)
      ""
    (concat
     (format evil-owl-header-format
             (propertize group-name 'face 'evil-owl-group-name))
     "\n")))

(defun evil-owl--display-string (group-alist entry-string-fn)
  (mapconcat
   (lambda (group)
     (let ((header (evil-owl--header-string (car group)))
           (body (mapconcat entry-string-fn (cdr group) "")))
       (concat header body)))
   group-alist
   evil-owl-separator))

;; ** Registers
(defun evil-owl--get-register (reg)
  "Get the contents of REG as a string."
  (when-let ((contents (evil-get-register reg t)))
    (cond
     ((stringp contents)
      (when (and evil-owl-register-char-limit
                 (> (length contents) evil-owl-register-char-limit))
        (setq contents (substring contents 0 evil-owl-register-char-limit)))
      (replace-regexp-in-string "\n" "^J" contents))
     ((vectorp contents)
      (key-description contents)))))

(defun evil-owl--register-entry-string (reg)
  (let* ((contents (evil-owl--get-register reg))
         (spec (format-spec-make ?r (propertize (char-to-string reg)
                                                'face 'evil-owl-entry-name)
                                 ?s contents)))
    (if (cl-plusp (length contents))
        (concat (format-spec evil-owl-register-format spec) "\n")
      "")))

(defun evil-owl--registers-display-string ()
  (evil-owl--display-string evil-owl-register-group-alist
                            #'evil-owl--register-entry-string))

;; ** Marks
(defun evil-owl--global-marker-p (mark)
  (or (<= ?A mark ?Z)
      (and evil-jumps-cross-buffers (memq mark '(?` ?')))))

(defun evil-owl--get-mark (mark)
  (when-let* ((pos (condition-case nil
                       (evil-get-marker mark)
                     ;; Some marks error if their use conditions
                     ;; haven't been met (e.g. '> assumes that there's
                     ;; a previous/current visual selection)
                     (error nil)))
              (buffer (cond ((numberp pos) (current-buffer))
                            ((markerp pos) (marker-buffer pos)))))
    (with-current-buffer buffer
      (let ((line (line-number-at-pos pos))
            (column (save-excursion
                      (goto-char pos)
                      (current-column))))
        (list line column (current-buffer))))))

(defun evil-owl--mark-entry-string (mark)
  (if-let ((pos-info (evil-owl--get-mark mark)))
      (cl-destructuring-bind (line column buffer) pos-info
        (let ((format (if (evil-owl--global-marker-p mark)
                          evil-owl-global-mark-format
                        evil-owl-local-mark-format))
              (spec (format-spec-make ?m (propertize (char-to-string mark)
                                                     'face 'evil-owl-entry-name)
                                      ?l line
                                      ?c column
                                      ?b buffer)))
          (concat (format-spec format spec) "\n")))
    ""))

(defun evil-owl--marks-display-string ()
  (evil-owl--display-string evil-owl-mark-group-alist
                            #'evil-owl--mark-entry-string))

;; * Posframe
;; ** Show / Hide
(defconst evil-owl--buffer " *evil-owl*"
  "The buffer name for the popup.")

(defvar evil-owl--timer nil
  "The timer for the popup.")

;; TODO: probably rename these functions to be more description
;; e.g. `evil-owl--show' --> `evil-owl--show-popup'
(defun evil-owl--show (string)
  (when (posframe-workable-p)
  (when (and (posframe-workable-p) (not (minibufferp)))
    (apply #'posframe-show
           evil-owl--buffer
           :string string
           :position (point)
           evil-owl-extra-posframe-args)
    ;; match evil's behavior
    (posframe-funcall evil-owl--buffer
                      (lambda () (setq-local truncate-lines t)))))

(defun evil-owl--idle-show (string)
  (setq evil-owl--timer
        (run-at-time evil-owl-idle-delay nil #'evil-owl--show string)))

(defun evil-owl--hide ()
  (when evil-owl--timer
    (cancel-timer evil-owl--timer)
    (setq evil-owl--timer nil))
  (posframe-delete evil-owl--buffer))

;; ** Keybindings
(defvar evil-owl-popup-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<escape>") #'keyboard-quit)
    (define-key map (kbd "C-g") #'keyboard-quit)
    (define-key map (kbd "C-b") #'evil-owl-scroll-popup-up)
    (define-key map (kbd "C-f") #'evil-owl-scroll-popup-down)
    map)
  "Keymap applied when the popup is active.")

(defun evil-owl-scroll-popup-up ()
  "Scroll the popup up one page."
  (interactive)
  (condition-case nil
      (posframe-funcall evil-owl--buffer #'scroll-down)
    (beginning-of-buffer nil)))

(defun evil-owl-scroll-popup-down ()
  "Scroll the popup down one page."
  (interactive)
  (condition-case nil
      (posframe-funcall evil-owl--buffer #'scroll-up)
    (end-of-buffer nil)))

(defmacro evil-owl--with-popup-map (&rest body)
  "Execute BODY with `evil-owl-popup-map' as the sole keymap."
  (declare (indent 0))
  (let ((current-global-map (gensym "current-global-map")))
    `(let ((overriding-terminal-local-map nil)
           (overriding-local-map evil-owl-popup-map)
           (,current-global-map (current-global-map)))
       (unwind-protect
           (progn
             (use-global-map (make-sparse-keymap))
             ,@body)
         (use-global-map ,current-global-map)))))

;; TODO: probably reorganize this
;; TODO: check if this conflicts with macros
(defun evil-owl--read-register-or-mark (&rest _)
  "Read a register or mark character.
This function allows executing commands in `evil-owl-popup-map', and
the keys of such commands will not be read."
  (evil-owl--with-popup-map
    (catch 'char
      (while t
        (let* ((keys (read-key-sequence nil nil t))
               (cmd (key-binding keys)))
          (cond
           (cmd
            (call-interactively cmd))
           ((and (stringp keys) (= (length keys) 1))
            (throw 'char (aref keys 0)))
           (t
            ;; Keys that are represented with vectors and not
            ;; strings (e.g. delete and f3) are not valid registers
            ;; or marks.
            (user-error "%s is undefined" (key-description keys)))))))))

;; * Minor Mode
;; TODO: maybe move this one to the posframe section or reorganize everything?
(defun evil-owl--call-with-popup (fn display-fn)
  (apply
   #'funcall-interactively
   fn
   (unwind-protect
       (progn
         (evil-owl--idle-show (funcall display-fn))
         (cl-letf (((symbol-function 'evil-read-key) #'evil-owl--read-register-or-mark)
                   ((symbol-function 'read-char) #'evil-owl--read-register-or-mark))
           (advice-eval-interactive-spec (cl-second (interactive-form fn)))))
     (evil-owl--hide))))

(cl-defmacro evil-owl--define-wrapper (name &key wrap display)
  (declare (indent defun))
  (cl-assert (symbolp name))
  (cl-assert (commandp wrap))
  (cl-assert (functionp display))
  `(evil-define-command ,name ()
     ,(format "Wrapper function for `%s' that shows a posframe preview." wrap)
     ,@(evil-get-command-properties wrap)
     (interactive)
     (setq this-command #',wrap)
     (evil-owl--call-with-popup #',wrap #',display)))

(evil-owl--define-wrapper evil-owl-use-register
  :wrap evil-use-register
  :display evil-owl--registers-display-string)

(evil-owl--define-wrapper evil-owl-execute-macro
  :wrap evil-execute-macro
  :display evil-owl--registers-display-string)

(evil-owl--define-wrapper evil-owl-record-macro
  :wrap evil-record-macro
  :display evil-owl--registers-display-string)

(evil-owl--define-wrapper evil-owl-paste-from-register
  :wrap evil-paste-from-register
  :display evil-owl--registers-display-string)

(evil-owl--define-wrapper evil-owl-set-marker
  :wrap evil-set-marker
  :display evil-owl--marks-display-string)

(evil-owl--define-wrapper evil-owl-goto-mark
  :wrap evil-goto-mark
  :display evil-owl--marks-display-string)

(evil-owl--define-wrapper evil-owl-goto-mark-line
  :wrap evil-goto-mark-line
  :display evil-owl--marks-display-string)

;;;###autoload
(define-minor-mode evil-owl-mode
  "A minor mode to preview marks and registers before using them."
  :global t
  :lighter evil-owl-lighter
  :keymap (let ((map (make-sparse-keymap)))
            (evil-define-key*
             'normal map
             [remap evil-record-macro] #'evil-owl-record-macro
             [remap evil-execute-macro] #'evil-owl-execute-macro
             [remap evil-use-register] #'evil-owl-use-register
             [remap evil-set-marker] #'evil-owl-set-marker
             [remap evil-goto-mark] #'evil-owl-goto-mark
             [remap evil-goto-mark-line] #'evil-owl-goto-mark-line)
            (evil-define-key*
             'insert map
             [remap evil-paste-from-register] #'evil-owl-paste-from-register)
            map))

;; * scratch
(progn ; test customizations
  (custom-set-faces
   '(evil-owl-group-name ((t (:inherit font-lock-function-name-face :weight bold :underline t))))
   '(evil-owl-entry-name ((t (:inherit font-lock-function-name-face)))))
  (set-face-background 'internal-border
                       (face-foreground 'font-lock-comment-face))
  (gsetq posframe-mouse-banish nil)
  (gsetq evil-owl-register-char-limit 100
         evil-owl-idle-delay 0.1)
  (gsetq evil-owl-extra-posframe-args
         `(
           :background-color ,(face-background 'mode-line)
           :right-fringe 8
           :width 50
           :height 20
           :poshandler posframe-poshandler-point-bottom-left-corner
           :internal-border-width 1
           )))
