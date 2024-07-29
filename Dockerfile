FROM pretix/standalone:2024.7.0
USER root
RUN pip3 install pretix-fontpack-free
RUN pip3 install pretix-pages
USER pretixuser
RUN cd /pretix/src && make production
