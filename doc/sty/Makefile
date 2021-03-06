#
# Copyright (C) 2011-2017 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 2 of
# the License, or (at your option) any later version.
#
# Auto-Multiple-Choice is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Auto-Multiple-Choice.  If not, see
# <http://www.gnu.org/licenses/>.

SHELL=/bin/sh

include ../../Makefile-all.conf

PACK=automultiplechoice

SAMPLES=$(wildcard sample-*.tex)

PDFLATEX=pdflatex -halt-on-error -interaction=nonstopmode
all: FORCE
	$(PDFLATEX) $(PACK).dtx
	$(MAKE) $(SAMPLES:.tex=.pdf)
	$(PDFLATEX) $(PACK).dtx
	makeindex -s gglo.ist -o $(PACK).gls $(PACK).glo
	makeindex -s gind.ist -o $(PACK).ind $(PACK).idx
	$(PDFLATEX) $(PACK).dtx
	$(PDFLATEX) $(PACK).dtx
	$(PERLPATH) ../../reproducible-pdf.pl --id $(PACK).pdf
	$(MAKE) postclean

styonly: $(PACK).dtx
	$(PDFLATEX) $<

sample-%.datetex.in: sample-%.tex
	$(PERLPATH) -pe 's!\\begin\{document\}!\\begin{document}\\pdfinfo{/CreationDate (D:@/PACKAGE_V_PDFDATE/@) /ModDate (D:@/PACKAGE_V_PDFDATE/@)}!;' < $< > $@

sample-%.datetex: sample-%.datetex.in
	$(MAKE) -C ../.. doc/sty/$@

sample-%.pdf: sample-%.datetex
	pdflatex -jobname sample-$* $<
	$(PERLPATH) ../../reproducible-pdf.pl --id $@

postclean:
	-rm -f pexa-*
	-rm -f $(foreach ext,amc aux dvi glo gls idx ilg ind log out toc xy xy1 xy2 xy3,*.$(ext))

clean: postclean
	rm -f *~
	rm -f $(PACK).sty
	rm -f *.pdf

FORCE: ;

.PHONY: all clean postclean FORCE
