classdef OptiTrackerSimple_London < handle
    % write a description of the class here.
    properties (Access = private)
        
        Block=4;
        SubjID=111;
        leglength=.51 %in meters (now natural step length!!)

        
        BoxRadius = 0.05; % Radius(Width/Height) of the boxes in meters
        SpawnInterval = 7; % The number of spawns per minute
        FPS = 20; % How often the figure should be updated
        Life = 5; % The Total life of the box in seconds
        HitLife = 1; % The life of the box, after it has been hit
        UseMouse = false; % Use mouse-cursor as input
        xRange = 2; % The range in the x-direction in meters
        yRange = 1; % The range in the y-direction in meters
        dummyMode = 0;
        natnetclient % object for connecting to Motive
        SerialPort = [];
        PrevTrigger = 0;
        TriggerInterval = 0.01/(60*60*24); %Minimum interval between triggers in seconds(converted to days)
        
        hFigure = [];
        hUser = [];
        hBox = [];
        hCross = [];
        hTitle = [];
        hMenu = [];
        fid = [];
        Cursor = struct('x',0,'y',0,'z',0);
    end
    methods
        % methods, including the constructor are defined in this block
        function obj = OptiTrackerSimple_London()
            if exist('natnet','class')
                % Connect to Motive on localhost (127.0.0.1)
                obj.natnetclient = natnet;
                obj.natnetclient.HostIP = '127.0.0.1';
                obj.natnetclient.ClientIP = '127.0.0.1';
                obj.natnetclient.ConnectionType = 'Multicast';
                obj.natnetclient.connect();
            end
            if ~exist('natnet','class') || obj.natnetclient.IsConnected == 0
                fprintf( 'NatNet client failed to connect\n' )
                fprintf( '\tMake sure the host is connected to the network\n' )
                fprintf( '\tand that the host and client IP addresses are correct\n\n' )
                obj.natnetclient = [];
                obj.UseMouse = true;
            end
            
            list = seriallist;
            if ~isempty(list)
                id = menu('Choose Triggerport',list);
                if id == 0
                    error('Cancelled by user');
                end
                list = str2double(strrep(list,'COM',''));
                try
                    NET.addAssembly([cd '/TriggerLib.dll']);
                    obj.SerialPort = TriggerLib.SerialPort(list(id));
                    addlistener(obj.SerialPort,'Trigger',@(~,~) obj.TriggerReceived);
                catch
                    obj.SerialPort = [];
                    fprintf( ['Opening serialport (COM' num2str(list(id)) ') failed\n'] )
                     %error('No COM connection')
                end
            else
                fprintf( 'No serialport was found\n' )
                %error('No COM connection')
            end
        end
        
        % Show 3d plot of scene with markers
        function Demo3(obj)
            if isempty(obj.natnetclient)
                fprintf( 'Demo3 is only available when Motive is connected\n' )
                return;
            end
            hFigure = figure();
            hAll = plot3(0,0,0,'ro','MarkerSize',10,'MarkerFaceColor','r');
            hold on
            hUser = plot3(0,0,0,'ro','MarkerSize',10,'MarkerFaceColor','b');
            hFloor = patch(obj.xRange*[-1 1 1 -1],obj.yRange*[0 0 1 1],'r','FaceAlpha',0.3);
            hold on
            axis equal
            xlim([-0.5 0.5])
            ylim([-0.2 1])
            zlim([-0.2 0.5])
            xlabel('X')
            ylabel('Y')
            zlabel('Z')
            view(40,30);
            
            tStart = tic();
            tUpdate = -1;
            while ishandle(hFigure)
                tNow = toc(tStart);
                if (tNow-tUpdate)>1/obj.FPS
                    [Markers,ToeID,XYZ] = obj.getMarkers();
                    if ~isempty(Markers)
                        set(hAll,'XData',XYZ(1,:),'YData',-XYZ(3,:),'ZData',XYZ(2,:));
                        set(hUser,'XData',Markers{ToeID}.x,'YData',-Markers{ToeID}.z,'ZData',Markers{ToeID}.y);
                        set(hFloor,'XData',obj.xRange*[-1 1 1 -1],'YData',obj.yRange*[0 0 1 1]);
                    end
                    tUpdate = tNow;
                    drawnow
                end
            end
        end
        
        % Show 2d plot of scene with user-marker
        function Demo(obj)
            if isempty(obj.hFigure) || ~ishandle(obj.hFigure)
                obj.PrepareFigure();
                set(obj.hBox,'visible','off');
                set(obj.hUser,'visible','on');
            end
            tStart = tic();
            tUpdate = -1;
            while ishandle(obj.hFigure)
                tNow = toc(tStart);
                if (tNow-tUpdate)>1/obj.FPS
                    [Markers,ToeID] = obj.getMarkers();
                    if ~isempty(Markers)
                        if isstruct(Markers{1})
                            x = Markers{1}.x;
                            y = Markers{1}.y;
                        else
                            x = Markers{ToeID}.x;
                            y = -Markers{ToeID}.z;
                        end
                        set(obj.hUser,'XData',x,'YData',y);
                    end
                    tUpdate = tNow;
                    drawnow
                end
            end
        end
          
        % Start the game
        function Start(obj,Filename)
            % Prepare folder and file for saving
            %if nargin == 1
                %Filename = datestr(now,'yyyy-mm-dd_HH_MM_SS');
            %else
                Filename = ['Subj_',num2str(obj.SubjID),'_VGstepping_Block_',num2str(obj.Block), '_' datestr(now,'yyyy-mm-dd_HH_MM_SS')];
            %end
            obj.PrepareFigure();
            if ~exist('SavedData','dir')
                mkdir('SavedData');
            end
            obj.fid = fopen(['./SavedData/' Filename '.txt'],'w');


            n = 45;%Number of trials for each mode, 45 now
            Modes = {'Stand','Stand and watch','Step','Step on targets'};
%             ModeOrder = randsample(4,4)';
              ModeOrder=[4 3 2];
            YStandVis_Backward = @(t) (1-min(1,max(0,t*3)))*(obj.leglength);
            counter=0;
            for Mode = ModeOrder
                obj.dummyMode = Mode;
                fprintf(obj.fid,'%.8f;Mode;%i\r\n',now,Mode);
                h = text(0,0,Modes{Mode},'FontSize',40,'HorizontalAlignment','center');
                tic();
                while toc()<4 && obj.Update()
                    %Show infotext for 5 seconds
                end
                delete(h)
                disp(Modes{Mode});
                for i = 1:n %loop for trials
                    counter=counter + 1; 
                    if ~isempty(obj.natnetclient) && Mode~=2
                        takename=sprintf('Subject %g Block %g trial %g',obj.SubjID, obj.Block,counter); %for motive recordings
                        obj.natnetclient.setTakeName(takename);
                    end
                    if ~obj.Update()
                        fclose(obj.fid);
                        return;
                    end
                    disp([Modes{Mode} ' ' num2str(i) '/' num2str(n) ' - Prepare']);
%                     sound(sin(1:1000)) %first sound
                    tic();
                    if Mode == 2
                        while toc()<1 && obj.Update(0,0)
                            %1 second prepare
                        end
                    else
                        while toc()<1 && obj.Update()
                            %1 second prepare
                        end
                    end
                    if obj.Update()
                        disp([Modes{Mode} ' ' num2str(i) '/' num2str(n) ' - Test']);
                        
                        % Update object visisbility based on mode
                        offset = 0;
                        switch(Mode)
                            case 1 %stand
                                set(obj.hBox,'Visible','off');
                                set(obj.hUser,'Visible','off');
                                set(obj.hCross,'Visible','off');
                            case 2 %Stand Vis
                                set(obj.hBox,'Visible','on');
                                set(obj.hUser,'Visible','on');
                                set(obj.hCross,'Visible','on');
                            case 3 %Step
                                set(obj.hBox,'Visible','off');
                                set(obj.hUser,'Visible','off');
                                set(obj.hCross,'Visible','off');
                            case 4 %Step Vis
                                set(obj.hBox,'Visible','on');
                                Offsets = [0 -obj.BoxRadius obj.BoxRadius]; %shorter longer or step length
                                offset = Offsets(randi(length(Offsets)));
                                Y_offset = (obj.leglength) + obj.BoxRadius*[-1 -1 1 1]+offset;
                                set(obj.hBox,'YData',Y_offset);
                                set(obj.hUser,'Visible','on');
                                set(obj.hCross,'Visible','on');
                        end
                        fprintf(obj.fid,'%.8f;BoxPos;%.8f\r\n',now,(obj.leglength)+offset);
                        obj.SendTrigger(); %trial start trigger
      
                        tic();

                        if ~isempty(obj.natnetclient)&& Mode~=2
                            obj.natnetclient.startRecord() %start motive recording
                        end
                        hit = false;
                        
                        %Send start-sound
                        obj.Update(); %want to see initially blue circle
                        tic()
                        sound(sin((1:3000)))
                        while toc()<1 && obj.Update()
                        end
                        while toc()<4
                            %5 second test
                            if Mode == 2 || Mode ==4 %
                             set(obj.hUser,'visible','on') % change to on to see blue dot 
                            end
%                             else
                                [FigureOpen,x,y] = obj.Update();
                            %end

                            if FigureOpen
                                if ~hit && ~isempty(x)
                                    xd = abs(x);
                                    yd = abs(y-(obj.leglength+offset));
                                    
                                    % Update box if hit
                                    if max(xd,yd)<obj.BoxRadius
                                         set(obj.hBox,'FaceColor','g');
                                        hit = true;
                                        if Mode ~= 2
                                            fprintf(obj.fid,'%.8f;HitBox\r\n',now);
                                        end
                                        drawnow
                                    end
                                end
                            else
                                break;
                            end
  
                        end
                        
                        %Send stop-sound & trigger
                        if Mode==4 || Mode==2 %visible again before box disappears
                            set(obj.hUser,'visible','on')
                        end
                        fprintf(obj.fid,'%.8f;TrialEnd\r\n',now);
                        obj.SendTrigger(); %stop trigger
                        sound([sin((1:1000)/2) zeros(1,1000) sin((1:1000)/2)])
                        
                        if ~isempty(obj.natnetclient)&& Mode~=2
                            obj.natnetclient.stopRecord();
                        end
                        
                        if Mode == 2
                            abcd = obj.Update(0,YStandVis_Backward(0));
                        else
                            abcd = obj.Update();
                        end
                        if(abcd)
                            % Hide objects when test is finished
                            tic();
                            while toc()<0.75 && obj.Update() %wait to give user feedback endpoint error
                            end
                            set(obj.hBox,'Visible','off');
                            set(obj.hBox,'FaceColor','r');
                            disp([Modes{Mode} ' ' num2str(i) '/' num2str(n) ' - Goback']);
                            tic();
                            if Mode == 2
                                set(obj.hUser,'Visible','on')
                                while toc()<3.25 && obj.Update(0,YStandVis_Backward(toc()/3.25))
                                    %Wait 4 seconds to let the user go back
                                end
                            else
                                while toc()<3.25 && obj.Update()
                                    %Wait 4 seconds to let the user go back
                                end
                            end
                        end
                    end
                end
            end
            fclose(obj.fid);
        end
    end
    
    methods (Access = private)
        function [FigureOpen,x,y] = Update(obj,X,Y)
            FigureOpen = ishandle(obj.hFigure);
            [Markers,ToeID] = obj.getMarkers();
            x = [];
            y = [];
            if ~isempty(Markers)
                ts = now;
                for i = 1:length(Markers)
                    if isstruct(Markers{i}) %if structure then its a cursor
                        fprintf(obj.fid,'%.8f;Cursor;%.8f;%.8f;%.8f\r\n',ts,Markers{i}.x,Markers{i}.y,Markers{i}.z);
                    else
                        fprintf(obj.fid,'%.8f;Marker;%d;%.8f;%.8f;%.8f\r\n',ts,Markers{i}.ID,Markers{i}.x,Markers{i}.y,Markers{i}.z);
                    end
                end
                if isstruct(Markers{1})
                    x = Markers{1}.x;
                    y = Markers{1}.y;%flipped for upside down cam
                else
                    x = Markers{ToeID}.x;
                    y = -Markers{ToeID}.z; %flipped for upside down cam
                end
                fprintf(obj.fid,'%.8f;UserXY;%.8f;%.8f;%d\r\n',ts,x,y,ToeID);
                if nargin == 3
                    x = X;
                    y = Y;
                    set(obj.hUser,'XData',x,'YData',y);
                else
                    if obj.dummyMode ~= 2
                        set(obj.hUser,'XData',x,'YData',y);
                    end
                end
                drawnow
            end
        end
        function SendTrigger(obj)
            if ~isempty(obj.SerialPort)
                fprintf(obj.fid,'%.8f;TriggerOutStart\r\n',now);
                obj.SerialPort.SendTrigger(1);
                fprintf(obj.fid,'%.8f;TriggerOutEnd\r\n',now);
            else
                fprintf(obj.fid,'%.8f;TriggerUnavailable\r\n',now);
            end
        end
        function TriggerReceived(obj)
            if (now-obj.PrevTrigger)>obj.TriggerInterval
                obj.PrevTrigger = now;
                fprintf(obj.fid,'%.8f;TriggerIn\r\n',now);
            end
        end
        % Clean up
        function delete(obj)
            if ~isempty(obj.natnetclient)
                obj.natnetclient.disconnect;
            end
            if ~isempty(obj.SerialPort)
                obj.SerialPort.Close();
            end
        end
        
        % Prepare figure for visualizaions
        function PrepareFigure(obj)
            % Change outerposition for 2nd screen
            obj.hFigure = figure('units','normalized','outerposition',[0 0 1 1],...
                'Toolbar', 'none', 'Menu', 'none','Renderer','painters');
            set(gcf,'color','w')
            hAxis = gca();
            obj.hCross = plot(0,0,'kx','MarkerSize',12,'LineWidth',2,'visible','off');
            hold on
            plot([-1 -1 1 1],[-1 1 -1 1],'.','Color',[1 1 1]); % 1 m fra midten i alle retninger
            obj.hBox = fill(hAxis,obj.BoxRadius*[-1 1 1 -1],(obj.leglength) + obj.BoxRadius*[-1 -1 1 1],'r','visible','off');
            obj.hUser = plot(0,0,'bo','MarkerSize',8,'MarkerFaceColor','b','visible','off');
            obj.hTitle = title('');
            %plot(-0.06,0,'kx','MarkerSize',12,'LineWidth',2) MDO - Other foot?
            axis equal off
            xlimValues = get(gca,'xlim');
            ylimValues = get(gca,'ylim');
            xlim(xlimValues)
            ylim(ylimValues) %changed this to get start in middle of screen
            set(obj.hFigure,'WindowButtonMotionFcn',@(~,~) obj.getMouse(hAxis));
        end
        
        % Get all markers from Motive
        function [Markers,ToeID,XYZ] = getMarkers(obj)
            Markers = {};
            ToeID = 1; %how is it that this works?
            XYZ = [];
            if obj.UseMouse
                Markers{1} = obj.Cursor;
            elseif ~isempty(obj.natnetclient)
                frame = obj.natnetclient.getFrame();
                for i = 1:frame.LabeledMarker.Length
                    if ~isempty(frame.LabeledMarker(i))
                        Markers{end+1} = frame.LabeledMarker(i);
                    else
                        break;
                    end
                end
                for i = 1:frame.UnlabeledMarker.Length
                    if ~isempty(frame.UnlabeledMarker(i))
                        Markers{end+1} = frame.UnlabeledMarker(i);
                    else
                        break;
                    end
                end
                if nargout > 1 && ~isempty(Markers)
                    XYZ = cell2mat(cellfun(@(x) [x.x;x.y;x.z],Markers,'UniformOutput',false));
                    [~,ToeID] = min(sum((XYZ-repmat([0;0;-1],1,length(Markers))).^2));
                end
            end
        end
        
        % Get current mouseposition of axis
        function getMouse(obj,hAxis)
            cursor = get(hAxis,'currentpoint');
            obj.Cursor = struct('x',cursor(1,1),'y',cursor(1,2),'z',0);
        end
    end
end