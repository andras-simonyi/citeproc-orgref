;;; -*- lexical-binding: t; nameless-current-name: "cpror"; eval: (nameless-mode t); -*-

(require 'subr-x)
(require 'map)
(require 'ox)
(require 'let-alist)
(require 'org-element)
(require 'cl-lib)

(require 'citeproc)
(require 'cpr-itemgetters)

(defvar cpror-default-csl-style-file "/home/simka/projects/citeproc/styles/chicago-author-date.csl"
  "Default CSL style file.")

(defvar cpror-cite-link-types '("cite" "citealt" "citeyear")
  "List of supported cite link types.")

(defvar cpror-suppress-affixes-cite-link-types '("citealt")
  "List of cite link types for which citation affixes should be
  suppressed.")

(defvar cpror-suppress-first-author-cite-link-types '("citeyear")
  "List of cite link types for which the first author should be 
  suppressed.")

(defvar cpror-html-backends '(html twbs)
  "List of html-based org-mode export backends.")

(defvar cpror-latex-backends '(latex)
  "List of latex-based org-mode export backends.")

(defvar cpror-no-cite-links-backends '(ascii)
  "Backends for which cite linking should always be turned off.")

(defvar cpror-non-citeproc-backends '(beamer)
  "List of backends that shouldn't be processed by citeproc.")

(defvar cpror-locales-dir "/home/simka/projects/locales"
  "Directory containing csl locale files.")

(defvar cpror-html-bib-header "<h2 class='cpror-bib-h2'>Bibliography</h1>\n"
  "HTML bibliography header to use for html export.")

(defvar cpror-latex-bib-header "\\section*{Bibliography}\n\n"
  "HTML bibliography header to use for html export.")

(defvar cpror-org-bib-header "* Bibliography\n"
  "Org-mode bibliography header to use for export.")

(defvar cpror-suppress-bibliography nil
  "Don't insert bibliography during export.")

(defvar cpror-bibtex-export-use-affixes nil
  "Use separate prefix and suffix for bibtex export.")

(defvar cpror-link-cites t
  "Link cites to references.")

(defvar cpror-html-hanging-indent "1.5em"
  "The size of hanging-indent for html ouput in valid CSS units.
Used only when hanging-indent is activated by the used CSL
style.")

(defvar cpror-html-label-width-per-char "0.6em"
  "Character width in CSS units for calculating entry label widths.
Used only when second-field-align is activated by the used CSL
style.")

(defvar cpror-latex-hanging-indent "1.5em"
  "The size of hanging-indent for LaTeX ouput in valid LaTeX units.
Always used for LaTeX output.")

(defvar-local cpror-proc-cache nil
  "Cached citeproc processor for citeproc-orgref.
Its value is either nil or a list of the form
(PROC STYLE-FILE BIBTEX-FILE LOCALE).")

(defconst cpror-label-alist
  '(("bk." . "book")
    ("bks." . "book")
    ("book" . "book")
    ("chap." . "chapter")
    ("chaps." . "chapter")
    ("chapter" . "chapter")
    ("col." . "column")
    ("cols." . "column")
    ("column" . "column")
    ("figure" . "figure") 
    ("fig." .  "figure")
    ("figs." .  "figure")
    ( "folio" . "folio") 
    ("fol." .  "folio")
    ("fols." .  "folio")
    ("number" . "number") 
    ("no." .  "number")
    ("nos." .  "number")
    ("line" . "line")
    ("l." .  "line")
    ("ll." .  "line")
    ("note" . "note")
    ("n." .  "note")
    ("nn." .  "note")
    ("opus" . "opus") 
    ("op." .  "opus")
    ("opp." .  "opus")
    ("page" . "page")
    ("p." .  "page")
    ("pp." .  "page")
    ("paragraph" . "paragraph")
    ("para." .  "paragraph")
    ("paras." .  "paragraph")
    ("¶" . "paragraph")
    ("¶¶" . "paragraph")
    ("§" . "paragraph")
    ("§§" . "paragraph")
    ("part" . "part")
    ("pt." .  "part")
    ("pts." .  "part")
    ("section" . "section")
    ("sec." .  "section")
    ("secs." .  "section")
    ("sub verbo" . "sub verbo")
    ("s.v." .  "sub verbo")
    ("s.vv." . "sub verbo")
    ("verse" . "verse") 
    ("v." .  "verse")
    ("vv." .  "verse")
    ("volume" . "volume") 
    ("vol." .  "volume")
    ("vols." .  "volume"))
  "Alist mapping locator names to locators.")

(defconst cpror-label-regex
  (let ((labels (map-keys cpror-label-alist)))
    (concat "\\<\\("
	    (mapconcat (lambda (x) (s-replace "." "\\." x))
		       labels "\\|")
	    "\\)[ $]")))

(defun cpror-parse-locator-affix (s)
  "Parse string S as a cite's locator and affix description.
Return an alist with `locator', `label', `prefix' and `suffix'
keys."
  (if (s-blank-p s) nil
    (let ((label-matches (s-matched-positions-all cpror-label-regex s 1))
	  (digit-matches (s-matched-positions-all "\\<\\w*[[:digit:]]+" s))
	  (comma-matches (s-matched-positions-all "," s))
	  label locator prefix suffix location)
      (let ((last-comma-pos (and comma-matches
				 (cdr (-last-item comma-matches)))))
	(if (or label-matches digit-matches)
	    (let (label-exp loc-start loc-end)
	      (if (null label-matches)
		  (setq loc-start (caar digit-matches)
			loc-end (cdr (-last-item digit-matches))
			label "page")
		(progn
		  (setq label-exp (substring s (caar label-matches) (cdar label-matches))
			label (assoc-default label-exp cpror-label-alist))
		  (if (null digit-matches)
		      (setq loc-start (caar label-matches)
			    loc-end (cdr (-last-item label-matches)))
		    (setq loc-start (min (caar label-matches) (caar digit-matches))
			  loc-end (max (cdr (-last-item label-matches))
				       (cdr (-last-item digit-matches)))))))
	      (when (> loc-start 0) (setq prefix (substring s 0 loc-start)))
	      (if (and last-comma-pos (> last-comma-pos loc-end))
		  (setq suffix (substring s last-comma-pos)
			loc-end (1- last-comma-pos))
		(setq loc-end nil))
	      (setq location (substring s loc-start loc-end)
		    locator (if label-exp (s-replace label-exp "" location) location)
		    locator (s-trim locator)))
	  (if last-comma-pos
	      (setq prefix (substring s 0 (1- last-comma-pos))
		    suffix (substring s last-comma-pos))
	    (setq prefix s))))
      `((locator . ,locator) (label . ,label) (location . ,location)
	(prefix . ,prefix) (suffix . ,suffix)))))

(defun cpror-in-fn-p (elt)
  "Whether org element ELT is in a footnote."
  (let ((curr (org-element-property :parent elt))
	result)
    (while (and curr (not result))
      (when (memq (org-element-type curr)
		  '(footnote-definition footnote-reference))
	(setq result (or (org-element-property :label curr) t)))
      (setq curr (org-element-property :parent curr)))
    result)) 

(defun cpror-get-option-val (opt)
  "Return the value of org-mode option OPT."
  (goto-char (point-min))
  (if (re-search-forward
       (concat "^#\\+" opt ":\\(.+\\)$")
       nil t)
      (let* ((match (match-data))
	     (start (elt match 2))
	     (end (elt match 3)))
	(s-trim (buffer-substring-no-properties start end)))
    nil))

(defun cpror-get-proc (bibtex-file)
  "Return a cpr processor to use and update the cache if needed."
  (let ((style-file (or (cpror-get-option-val "csl-style") cpror-default-csl-style-file))
	(locale (or (cpror-get-option-val "language") "en"))
	result)
    (-when-let ((c-proc c-style-file c-bibtex-file c-locale)
		cpror-proc-cache)
      (when (and (string= style-file c-style-file)
		 (string= locale c-locale))
	(progn
	  (unless (string= bibtex-file c-bibtex-file)
	    (setf (cpr-proc-getter c-proc)
		  (cpr-itgetter-from-bibtex bibtex-file)
		  (elt 1 cpror-proc-cache) bibtex-file)
	    (setq result c-proc)))))
    (or result
	(let ((proc (cpr-proc-create
		     style-file
		     (cpr-itgetter-from-bibtex bibtex-file)
		     (cpr-locale-getter-from-dir cpror-locales-dir)
		     locale)))
	  (setq cpror-proc-cache
		(list proc style-file bibtex-file locale))
	  proc))))

(defun cpror-links-and-notes()
  "Collect bib-related links and info about them."
  (let* ((elts (org-element-map (org-element-parse-buffer)
		   '(footnote-reference link) #'identity))
	 cite-links bib-links links-and-notes
	 (act-link-no 0)
	 (cite-links-count 0)
	 (footnotes-count 0))
    (dolist (elt elts)
      (if (eq 'footnote-reference (org-element-type elt))
	  (progn
	   (cl-incf footnotes-count)
	   ;; footnotes repesented as ('footnote <label> <link_n> ... <link_0>)
	   (push (list 'footnote (org-element-property :label elt))
		 links-and-notes))
	(let ((link-type (org-element-property :type elt)))
	  (cond
	   ((member link-type cpror-cite-link-types)
	    (push elt cite-links)
	    (cl-incf cite-links-count)
	    (let ((fn-label (cpror-in-fn-p elt))
		  ;; links as ('link <link-idx>)
		  (indexed (list 'link act-link-no elt)))
	      (cl-incf act-link-no)
	      (pcase fn-label
		;; not in footnote
		((\` nil) (push indexed links-and-notes))
		;; unlabelled, in the last footnote
		('t (push indexed (cddr (car links-and-notes))))
		;; labelled footnote
		(_ (let ((fn-with-label (--first (and (eq (car it) 'footnote)
						      (string= fn-label
							       (cadr it)))
						 links-and-notes)))
		     (if fn-with-label
			 (setf (cddr fn-with-label)
			       (cons indexed (cddr fn-with-label)))
		       (error "No footnote reference before footnote definition with label %s" fn-label)))))))
	   ((string= link-type "bibliography")
	    (push elt bib-links))))))
    (list (nreverse cite-links) bib-links links-and-notes cite-links-count footnotes-count)))

(defun cpror-assemble-link-info (links-and-notes link-count footnote-count
					    &optional all-links-are-notes)
  "Return position and note info using LINKS-AND-NOTES."
  (let (link-info
	(act-fn-no (let ((links-and-notes-count (length links-and-notes)))
		     (1+ (if all-links-are-notes
			     links-and-notes-count
			   footnote-count))))
	(act-cite-no link-count))
    (dolist (elt links-and-notes)
      (pcase (car elt)
	('link
	 (push (list
		:link (cl-caddr elt)
		:link-no (cadr elt)
		:cite-no (cl-decf act-cite-no)
		:fn-no (if all-links-are-notes
			   (cl-decf act-fn-no)
			 nil)
		:new-fn all-links-are-notes)
	       link-info))
	('footnote
	 (cl-decf act-fn-no)
	 (dolist (link (cddr elt))
	   (push (list
		  :link (cl-caddr link)
		  :link-no (cadr link)
		  :cite-no (cl-decf act-cite-no)
		  :fn-no act-fn-no)
		 link-info)))))
    link-info))

(defun cpror-link-to-citation (link footnote-no new-fn &optional capitalize-outside-fn)
  "Return a citeproc citation corresponding to org cite LINK.
If CAPITALIZE-OUTSIDE-FN is  non-nil then set the
`capitalize-first' slot of the citation struct to t when the link
is not in a footnote."
  (let* ((type (org-element-property :type link))
	 (path (org-element-property :path link))
	 (content (let ((c-begin (org-element-property :contents-begin link))
			(c-end (org-element-property :contents-end link)))
		    (if (and c-begin c-end)
			(buffer-substring-no-properties c-begin c-end)
		      nil)))
	 (itemids (split-string path ","))
	 (cites-ids (--map (cons 'id it)
			   itemids)))
    (cpr-citation-create
     :note-index footnote-no
     :cites
     (let ((cites
	    (if content
		(let* ((cites-rest (mapcar #'cpror-parse-locator-affix
					   (split-string content ";")))
		       (cites-no (length cites-ids))
		       (rest-no (length cites-rest))
		       (diff (- cites-no rest-no))
		       (cites-rest-filled (let* ()
					    (if (> diff 0)
						(-concat cites-rest (make-list diff nil))
					      cites-rest))))
		  (-zip cites-ids cites-rest-filled))
	      (mapcar #'list cites-ids))))
       (if (member type cpror-suppress-first-author-cite-link-types)
	   (cons (cons '(suppress-author . t) (car cites)) (cdr cites))
	 cites))
     :capitalize-first (and capitalize-outside-fn
			    new-fn)
     :suppress-affixes (member type
			       cpror-suppress-affixes-cite-link-types))))
 
(defun cpror-element-boundaries (element)
  "Return the boundaries of an org ELEMENT.
Returns a (BEGIN END) list -- post-blank positions are not
considered when calculating END."
  (let ((begin (org-element-property :begin element))
	(end (org-element-property :end element))
	(post-blank (org-element-property :post-blank element)))
    (list begin (- end post-blank))))

(defun cpror-format-html-bib (bib parameters)
  "Format html bibliography BIB using formatting PARAMATERS."
  (let* ((char-width (car (s-match "[[:digit:].]+" cpror-html-label-width-per-char)))
	 (char-width-unit (substring cpror-html-label-width-per-char (length char-width))))
    (let-alist parameters 
      (concat "\n#+BEGIN_EXPORT html\n"
	      (when .second-field-align
		(concat "<style>.csl-left-margin{float: left; padding-right: 0em;} "
			".csl-right-inline{margin: 0 0 0 "
			(number-to-string (* .max-offset (string-to-number char-width)))
			char-width-unit ";}</style>"))
	      (when .hanging-indent
		(concat "<style>.csl-entry{text-indent: -"
			cpror-html-hanging-indent
			"; margin-left: "
			cpror-html-hanging-indent
			";}</style>"))
	      cpror-html-bib-header
	      bib
	      "\n#+END_EXPORT\n"))))

(defun cpror-format-latex-bib (bib)
  "Format LaTeX bibliography BIB."
  (concat "#+latex_header: \\usepackage{hanging}\n#+BEGIN_EXPORT latex\n"
		 cpror-latex-bib-header
		 "\\begin{hangparas}{" cpror-latex-hanging-indent "}{1}"
		 bib "\n\\end{hangparas}\n#+END_EXPORT\n"))

(defun cpror-bibliography (proc backend)
  "Return a bibliography using citeproc PROC."
  (cond ((memq backend cpror-html-backends)
	 (-let ((rendered (cpr-render-bib proc 'html (not cpror-link-cites))))
	   (cpror-format-html-bib (car rendered) (cdr rendered))))
	((memq backend cpror-latex-backends)
	 (cpror-format-latex-bib (car (cpr-render-bib proc 'latex (not cpror-link-cites)))))
	(t (concat cpror-org-bib-header
		   (car (cpr-render-bib proc 'org (or (memq backend cpror-no-cite-links-backends)
						      (not cpror-link-cites))))
		   "\n"))))

(defun cpror-append-and-render-citations (link-info proc backend)
  "Render citations using LINK-INFO and PROC.
Return the list of corresponding rendered citations."
  (let* ((is-note-style (cpr-style-cite-note (cpr-proc-style proc)))
	 (citations (--map (cpror-link-to-citation (plist-get it :link)
					      (plist-get it :fn-no)
					      (plist-get it :new-fn)
					      is-note-style)
			   link-info)))
    (cpr-proc-append-citations proc citations)
    (let* ((rendered
	    (cond ((memq backend cpror-html-backends)
		   (--map (concat "@@html:" it "@@")
			  (cpr-render-citations
			   proc 'html (not cpror-link-cites))))
		  ((memq backend cpror-latex-backends)
		   (--map (concat "@@latex:" it "@@")
			  (cpr-render-citations
			   proc 'latex (not cpror-link-cites))))
		  (t (cpr-render-citations
		      proc 'org (or (memq backend cpror-no-cite-links-backends)
				    (not cpror-link-cites)))))))
      (setq rendered (cl-loop for l-i in link-info
			      for rendered-citation in rendered
			      collect (if (plist-get l-i :new-fn)
					  (concat "[fn::" rendered-citation "]")
					rendered-citation)))
      (cpror-reorder-rendered-citations rendered link-info))))

(defun cpror-reorder-rendered-citations (rendered link-info)
  (let ((sorted (cl-sort link-info #'< :key (lambda (x) (plist-get x :link-no)))))
    (--map (elt rendered (plist-get it :cite-no)) sorted)))

(defun cpror-replace-links (&optional backend)
  "Replace cite and bib links with references.
BACKEND is the org export backend used. Returns nil."
  (interactive)
  (if (not (memq backend cpror-non-citeproc-backends))
      (-let (((cite-links bib-links links-and-notes link-count footnote-count)
	      (cpror-links-and-notes)))
	(when cite-links
	  ;; Deal with the existence and boundaries of the bib link
	  (-let* ((bl-count (length bib-links))
		  (bib-link (cond
			     ((= bl-count 1) (car bib-links))
			     ((> bl-count 1)
			      (error "Cannot process more then one bibliography links"))
			     ((= bl-count 0)
			      (error "Missing bibliography link"))))
		  (bibtex-file (org-element-property :path bib-link))
		  (proc (cpror-get-proc bibtex-file))
		  ((bl-begin bl-end)
		   (and bib-link (cpror-element-boundaries bib-link))))
	    (cpr-proc-clear proc)
	    (-let* ((link-info
		     (cpror-assemble-link-info links-and-notes link-count footnote-count
					  (cpr-style-cite-note (cpr-proc-style proc))))
		    (rendered-cites (cpror-append-and-render-citations link-info proc backend))
		    (rendered-bib (if cpror-suppress-bibliography ""
				    (cpror-bibliography proc backend)))
		    (offset 0)
		    (bib-inserted-p nil))
	      (cl-loop for rendered in rendered-cites
		       for link in cite-links
		       do
		       (-let* (((begin end) (cpror-element-boundaries link)))
			 (when (and bib-link (> begin bl-end))
			   ;; Reached a cite link after the bibliography link so
			   ;; we insert the rendered bibliography before it
			   (setf (buffer-substring (+ bl-begin offset) (+ bl-end offset))
				 rendered-bib)
			   (setq bib-inserted-p t)
			   (cl-incf offset (- (length rendered-bib) (- bl-end bl-begin))))
			 (when (and (string= "[fn::" (substring rendered 0 5))
				    (= (char-before (+ begin offset)) ?\s))
			   ;; Remove (a single) space before the footnote
			   (cl-decf begin 1))
			 (setf (buffer-substring (+ begin offset) (+ end offset))
			       rendered)
			 (cl-incf offset (- (length rendered) (- end begin)))))
	      (when (not bib-inserted-p)
		;; The bibliography link was the last one
		(setf (buffer-substring (+ bl-begin offset) (+ bl-end offset))
		      rendered-bib))))))
    (cpror-citelinks-to-legacy))
  nil)

(defun cpror-citelink-content-to-legacy (content)
  "Convert a parsed citelink content to a legacy one."
  (let* ((first-item (car (split-string content ";")))
	 (parsed (cpror-parse-locator-affix first-item))
	 prefix suffix)
    (let-alist parsed
      (if (not cpror-bibtex-export-use-affixes)
	  (concat .prefix .location .suffix)
	(progn
	  (setq prefix .prefix
		suffix (concat .suffix .location))
	  (if (null suffix) prefix (concat prefix "::" suffix)))))))

(defun cpror-citelinks-to-legacy ()
  "Replace cite link contents with their legacy org-refversions."
  (interactive)
  (let ((links (--filter (and (string= (org-element-property :type it) "cite")
			      (org-element-property :contents-begin it))
			 (org-element-map (org-element-parse-buffer)
			     'link #'identity)))
	(offset 0))
    (dolist (link links)
      (-let* (((begin end) (cpror-element-boundaries link))
	      (raw-link (org-element-property :raw-link link))
	      (c-begin (+ offset (org-element-property :contents-begin link)))
	      (c-end (+ offset (org-element-property :contents-end link)))
	      (content (buffer-substring-no-properties c-begin c-end))
	      (new-content (cpror-citelink-content-to-legacy content))
	      (new-link (if (s-blank-p new-content)
			    (concat "[[" raw-link "]]")
			  (concat "[[" raw-link "][" new-content "]]"))))
	(setf (buffer-substring (+ begin offset) (+ end offset))
	      new-link)
	(cl-incf offset (- (length new-link) (- end begin)))))))

(defun cpror-setup ()
  (add-hook 'org-export-before-parsing-hook #'cpror-replace-links))

(provide 'citeproc-orgref)

;;; citeproc-orgref.el ends here
