;;; poporg.el --- Pop a region in a separate buffer for Org editing

;; Copyright © 2013 Ubity inc.

;; Author: François Pinard

;; This is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This pops a separate edit buffer in Org mode to edit the contents
;; of a comment or string, then reinserts the modified text in place
;; once the edition is done.  See https://github.com/pinard/poporg.

;;; Code:

(defvar poporg-data nil
  "List of (BUFFER OVERLAY PREFIX) triplets.
For each edit BUFFER, there is an OVERLAY graying out the edited
block comment or string in the original program buffer, and a
PREFIX that was removed from all lines in the edit buffer and
which is going to be prepended to these lines before returning
them the original buffer.")

(defvar poporg-edit-hook nil
  "List of hooks to run once a new editing buffer has been filled.")

(defvar poporg-edit-exit-hook nil
  "List of hooks to run prior to moving back an editing buffer.")

(defface poporg-edited-face
  '((((class color) (background light))
     (:foreground "gray"))
    (((class color) (background dark))
     (:foreground "gray")))
  "Face for a region while it is being edited.")

(defun poporg-current-line ()
  "Return the contents of the line where the point is."
  (buffer-substring-no-properties
   (save-excursion (beginning-of-line) (point))
   (save-excursion (end-of-line) (point))))

(defun poporg-dwim ()
  (interactive)
  "Single overall command for poporg (a single keybinding may do it all).
Edit either the active region, the comment or string containing
the cursor, after the cursor, else before the cursor.  Within a
*poporg* edit buffer however, rather complete and exit the edit."
  (cond ((assq (current-buffer) poporg-data) (poporg-edit-exit))
        ((use-region-p) (poporg-edit-region (region-beginning) (region-end)))
        ((poporg-dwim-1 (point)))
        ((poporg-dwim-1
          (let ((location (next-single-property-change (point) 'face)))
            (or location (point-max)))))
        ((and (> (point) (point-min)) (poporg-dwim-1 (1- (point)))))
        ((poporg-dwim-1
          (let ((location (previous-single-property-change (point) 'face)))
            (if (and location (> location (point-min)))
                (1- location)
              (point-min)))))
        (t (error "Nothing to edit!"))))

(defun poporg-dwim-1 (location)
  "Possibly edit the comment or string surrounding LOCATION.
The edition occurs in a separate buffer.  Return nil if nothing to edit."
  (when location
    (let ((face (get-text-property location 'face)))
      (cond ((eq face 'font-lock-comment-delimiter-face)
             (poporg-edit-comment location)
             t)
            ((eq face 'font-lock-comment-face)
             (poporg-edit-comment location)
             t)
            ((eq face 'font-lock-doc-face)
             ;; As in Emacs Lisp doc strings.
             (poporg-edit-string location)
             t)
            ((eq face 'font-lock-string-face)
             ;; As in Python doc strings.
             (poporg-edit-string location)
             t)))))

(defun poporg-edit-comment (location)
  "Discover the extent of current comment, then edit it in Org mode.
Point should be within a comment.  The edition occurs in a separate buffer."
  (require 'rebox)
  (let (start end prefix)
    (rebox-find-and-narrow)
    (setq start (point-min)
          end (point-max))
    (widen)
    (goto-char start)
    (skip-chars-backward " ")
    (setq start (point))
    ;; Set PREFIX.
    (skip-chars-forward " ")
    (skip-chars-forward comment-start)
    (skip-chars-forward " ")
    (setq prefix (buffer-substring-no-properties start (point))
          prefix-regexp (regexp-quote prefix))
    ;; Edit our extended comment.
    (poporg-edit-region start end prefix)))

(defun poporg-edit-comment-0 (location)
  "Discover the extent of current comment, then edit it in Org mode.
Point should be within a comment.  The edition occurs in a separate buffer."
  ;; FIXME: This is experimental.
  (let (start end prefix)
    (poporg-find-span '(font-lock-comment-delimiter-face
                        font-lock-comment-face))
    (goto-char start)
    (skip-chars-backward " ")
    (setq start (point))
    ;; Set PREFIX.
    (skip-chars-forward " ")
    (skip-chars-forward comment-start)
    (if (looking-at " ")
        (forward-char))
    (setq prefix (buffer-substring-no-properties start (point))
          prefix-regexp (regexp-quote prefix))
    ;; Edit our extended comment.
    (poporg-edit-region start end prefix)))

(defun poporg-edit-string (location)
  "Discover the extent of current string, then edit it in Org mode.
Point should be within a string.  The edition occurs in a separate buffer."
  ;; FIXME: This is experimental.
  (let (start end prefix)
    ;; If Python, presume the string is sextuple-quoted.
    (when (eq major-mode 'python-mode)
      (save-excursion
        (setq end (search-forward "\"\"\"" nil t))
        (when end
          (setq end (- end 3))))
      (save-excursion
        (setq start (search-backward "\"\"\"" nil t))
        (when start
          (forward-char 3)
          (skip-chars-forward "\\\\\n")
          (setq start (point)))))
    ;; Set END.
    (if end
        (goto-char end)
      (goto-char (or (next-single-property-change location 'face)
                     (point-max)))
      (skip-chars-backward "\"'\\\n"))
    (when (looking-at "\n")
      (forward-char))
    (setq end (point))
    ;; Set START.
    (if start
        (goto-char start)
      (goto-char (or (previous-single-property-change location 'face)
                     (point-min)))
      (skip-chars-forward "\"'\\\\\n"))
    (setq start (point))
    ;; Set PREFIX.
    (skip-chars-forward " ")
    (setq prefix (buffer-substring-no-properties start (point)))
    ;; Edit our string.
    (poporg-edit-region start end prefix)))

(defun poporg-edit-string-0 (location)
  "Discover the extent of current string, then edit it in Org mode.
Point should be within a string.  The edition occurs in a separate buffer."
  ;; FIXME: This is experimental.
  (let (start end prefix)
    (poporg-find-span '(font-lock-doc-face font-lock-string-face))
    ;; Set END.
    (goto-char (or (next-single-property-change location 'face)
                   (point-max)))
    (skip-chars-backward "\"'\\\n")
    (when (looking-at "\n")
      (forward-char))
    (setq end (point))
    ;; Set START.
    (goto-char (or (previous-single-property-change location 'face)
                   (point-min)))
    (skip-chars-forward "\"'\\\\\n")
    (setq start (point))
    ;; Set PREFIX.
    (skip-chars-forward " ")
    (setq prefix (buffer-substring-no-properties start (point)))
    ;; Edit our string.
    (poporg-edit-region start end prefix)))

;; FIXME: Temporary debugging code.
(defvar debug-overlay (make-overlay 1 1))
(overlay-put debug-overlay 'face 'poporg-edited-face)

(defun poporg-edit-region-0 (start end &optional minimal-prefix)
  (move-overlay debug-overlay start end (current-buffer)))

(defun poporg-edit-region (start end prefix)
  "Setup an editing buffer in Org mode with region contents from START to END.
A prefix common to all buffer lines, and to PREFIX as well, gets removed."
  (interactive "r")
  ;; Losely reduced out of PO mode's po-edit-string.
  (let ((start-marker (make-marker))
        (end-marker (make-marker)))
    (set-marker start-marker start)
    (set-marker end-marker end)
    (let ((buffer (current-buffer))
          (edit-buffer (generate-new-buffer (concat "*" (buffer-name) "*")))
          (overlay (make-overlay start end))
          (string (buffer-substring start end)))
      ;; Dim and protect the original text.
      (overlay-put overlay 'face 'poporg-edited-face)
      (overlay-put overlay 'intangible t)
      (overlay-put overlay 'read-only t)
      ;; Initialize a popup edit buffer.
      (pop-to-buffer edit-buffer)
      (insert string)
      (goto-char (point-min))
      (org-mode)
      ;; Reduce prefix as needed.
      (goto-char (point-min))
      (while (not (eobp))
        (setq prefix (or (fill-common-string-prefix
                          prefix (poporg-current-line))
                         ""))
        (forward-line 1))
      ;; Remove common prefix.
      (goto-char (point-min))
      (while (not (eobp))
        (delete-char (length prefix))
        (forward-line 1))
      (set-buffer-modified-p nil)
      ;; Save data and possibly activate hooks. 
      (unless poporg-data
        (push 'poporg-kill-buffer-query kill-buffer-query-functions)
        (add-hook 'kill-buffer-hook 'poporg-kill-buffer-routine))
      (push (list edit-buffer overlay prefix) poporg-data)
      ;; All set up for edition.
      (goto-char (point-min))
      (run-hooks 'poporg-edit-hook))))

(defun poporg-edit-exit ()
  "Exit the edit buffer, replacing the original region."
  (interactive)
  (let* ((edit-buffer (current-buffer))
         (triplet (assq edit-buffer poporg-data))
         (overlay (cadr triplet))
         (buffer (overlay-buffer overlay))
         (prefix (caddr triplet)))
    (if (not buffer)
        (error "Original buffer vanished")
      (run-hooks 'poporg-edit-exit-hook)
      (when (buffer-modified-p)
        ;; Reinsert the prefix.
        (goto-char (point-min))
        (while (not (eobp))
          (insert prefix)
          (forward-line 1))
        ;; Move everything back in place.
        (let ((string (buffer-substring-no-properties (point-min) (point-max)))
              (start (overlay-start overlay))
              (end (overlay-end overlay)))
          (with-current-buffer buffer
            (goto-char start)
            (delete-region start end)
            (insert string))
          (set-buffer-modified-p nil)))
      (unless (one-window-p)
        (delete-window)))
  ;; Killing the buffer triggers a cleanup through the kill hook.
  ;; EDIT-BUFFER is given explicitly as DELETE-WINDOW changed things.
  (kill-buffer edit-buffer)))

(defun poporg-find-span (faces)
  "Set START and END around point, extending over text having any of FACES.
The extension goes over single newlines and their surrounding whitespace.
START and END should be already bound within the caller."
  ;; FIXME: This is experimental.
  ;; Set START.
  (save-excursion
    (goto-char (or (previous-single-property-change (point) 'face)
                   (point-min)))
    (setq start (point))
    (skip-chars-backward " ")
    (when (= (preceding-char) ?\n)
      (forward-char -1)
      (skip-chars-backward " ")
      (while (and (not (bobp))
                  (memq (get-text-property (1- (point)) 'face) comment-faces))
        (goto-char (or (previous-single-property-change (1- (point)) 'face)
                       (point-min)))
        (setq start (point))
        (skip-chars-backward " ")
        (when (= (preceding-char) ?\n)
          (forward-char -1)
          (skip-chars-backward " ")))))
  ;; Set END.
  (save-excursion
    (goto-char (or (next-single-property-change (point) 'face)
                   (point-max)))
    (setq end (point))
    (skip-chars-forward " ")
    (when (= (following-char) ?\n)
      (forward-char)
      (skip-chars-forward " ")
      (while (memq (get-text-property (point) 'face) faces)
        (goto-char (or (next-single-property-change (point) 'face)
                       (point-max)))
        (setq end (point))
        (skip-chars-forward " ")
        (when (= (following-char) ?\n)
          (forward-char)
          (skip-chars-forward " "))))))

(defun poporg-kill-buffer-query ()
  "Beware any killing that might lose pending edits."
  (let ((triplet (assq (current-buffer) poporg-data)))
    (if triplet
        (or (not (buffer-modified-p))
            (yes-or-no-p "Really abandon this edit? "))
      (let ((data poporg-data)
            (value t))
        (while data
          (let ((buffer (overlay-buffer (cadar data))))
            (if (not (eq buffer (current-buffer)))
                (setq data (cdr data))
              (pop-to-buffer (caar data))
              (message "First, either complete or kill this edit.")
              (setq data nil
                    value nil))))
        value))))

(defun poporg-kill-buffer-routine ()
  "Cleanup an edit buffer whenever killed."
  (let ((triplet (assq (current-buffer) poporg-data)))
    (when triplet
      (let* ((overlay (cadr triplet))
             (buffer (overlay-buffer overlay)))
        (when buffer
          (delete-overlay overlay)
          (setq poporg-data (delq triplet poporg-data))
          (unless poporg-data
            (setq kill-buffer-query-functions
                  (delq 'poporg-kill-buffer-query kill-buffer-query-functions))
            (remove-hook 'kill-buffer-hook 'poporg-kill-buffer-routine)))))))

(provide 'poporg)
  
;;; poporg.el ends here
