FROM pretix/standalone:2026.1.0
USER root
RUN pip3 install pretix-fontpack-free
RUN pip3 install pretix-pages
USER pretixuser
RUN cd /pretix/src && make production
