FROM alpine:3.17
ENV FLASK_PORT 8080
ENV FLASK_DOCUMENTROOT /var/flaskapp
ENV FLASK_USER flaskuser
RUN mkdir -p $FLASK_DOCUMENTROOT    
RUN adduser -h $FLASK_DOCUMENTROOT  -D  -s /bin/sh  $FLASK_USER    
WORKDIR $FLASK_DOCUMENTROOT
COPY .  .
RUN chown -R  $FLASK_USER:$FLASK_USER $FLASK_DOCUMENTROOT
RUN  apk update &&  apk add python3 py3-pip --no-cache
RUN pip3 install -r requirements.txt 
EXPOSE $FLASK_PORT
USER $FLASK_USER
CMD ["app.py"]
ENTRYPOINT ["python3"]
