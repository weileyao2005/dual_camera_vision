function main()
    global cams statusText vis  
    
    % ... 其他代码 ... 
    %% ========================== 主函数入口 ==========================
    Fig = figure('Position',[500,200,980,800], 'Name','双摄像头追踪系统',...
        'CloseRequestFcn',@closeApp); % 绑定关闭回调

    %% ====================== 全局参数初始化 ======================
    min_features = 20;   
    vis = initializeVisualization();
   
    %% ====================== 加载相机参数 ======================
    % 使用结构体存储相机参数
    cameraParams = loadCameraParams();
    
    % 检查相机参数是否成功加载
    if isempty(cameraParams) || isempty(cameraParams.K1)
        errordlg('相机参数加载失败，程序无法继续运行');
        close(Fig);
        return;
    end
    


    %% ====================== 摄像头结构体初始化 ======================
    cams = struct('Hobj',{}, 'tracker',{}, 'points',{}, 'flag',{}, 'axes',{},...
                 'imgSize',{}, 'descriptors',{}, 'frame',{}, 'currentPoints',{}, 'currentFeatures',{});

    %% ======================== GUI界面布局设置 ========================
    for camIdx = 1:2
        % 垂直布局参数
        panelHeight = 0.45;
        verticalMargin = 0.05;
        ypos = (0.55 - (camIdx-1)*panelHeight) - verticalMargin;
        
        % 创建面板容器
        panel = uipanel(Fig, 'Position',[0.05, ypos, 0.9, panelHeight-verticalMargin]);
        
        % 双视图布局
        camAxes = gobjects(1,2);
        camAxes(1) = axes(panel, 'Position',[0,    0, 0.5, 1], 'XTick',[], 'YTick',[]);
        camAxes(2) = axes(panel, 'Position',[0.5,  0, 0.5, 1], 'XTick',[], 'YTick',[]); 
        
        % 坐标轴设置
        axis(camAxes, 'image');
        title(camAxes(1), sprintf('摄像头%d视图', camIdx));

        %% ====================== 硬件初始化 ========================
        try
            % 设备检测
            devices = imaqhwinfo('winvideo');
            if numel(devices.DeviceIDs) < camIdx
                error('摄像头%d未连接', camIdx);
            end
            
           % 设备配置
            switch camIdx
                case 1  % 笔记本内置摄像头
                    videoFormat = 'YUY2_1280x720';  
                    colorSpace = 'rgb';          % 改为rgb
                    deviceID = 1; 
                case 2  % 外接摄像头
                    videoFormat = 'MJPG_1280x720'; 
                    colorSpace = 'rgb';            
                    deviceID = 2;
            end
            
            % 创建视频对象
            cams(camIdx).Hobj = videoinput('winvideo', deviceID, videoFormat);
            cams(camIdx).Hobj.ReturnedColorSpace = colorSpace;
            set(cams(camIdx).Hobj, 'FramesPerTrigger', 1);
            set(cams(camIdx).Hobj, 'TriggerRepeat', Inf);
            cams(camIdx).Hobj.Tag = sprintf('Cam%d', camIdx);
            
            % 预防性停止
            if isrunning(cams(camIdx).Hobj)
                stop(cams(camIdx).Hobj);
            end
            
            % 分辨率自动适配
            frameRes = sscanf(videoFormat, '%*[^_]_%dx%d');
            if ~isempty(frameRes)
                cams(camIdx).Hobj.ROIPosition = [0 0 frameRes(1) frameRes(2)];
            end
            
            % 获取初始帧
            triggerconfig(cams(camIdx).Hobj, 'manual');
            start(cams(camIdx).Hobj);
            initFrame = getsnapshot(cams(camIdx).Hobj);
            [height, width, ~] = size(initFrame);
            cams(camIdx).imgSize = [width, height];
            
            % 开启预览
            preview(cams(camIdx).Hobj);
        catch ME
            warning('摄像头%d初始化失败: %s', camIdx, ME.message);
            if exist('cams','var') && numel(cams)>=camIdx && ~isempty(cams(camIdx).Hobj)
                delete(cams(camIdx).Hobj);
            end
            cams(camIdx).Hobj = [];
        end

        %% ====================== 算法初始化 ========================
        cams(camIdx).tracker = vision.PointTracker(...
            'MaxBidirectionalError', 1, ...
            'NumPyramidLevels', 5);

        cams(camIdx).flag = 0;
        cams(camIdx).axes = camAxes;
    end

%% ======================= 控制面板 =========================
% 定义按钮样式
btnStyle = {'Style','togglebutton', 'FontSize',12, 'FontWeight','bold'};

% 创建状态显示文本（作为全局变量，这样可以在其他函数中访问）

statusText = uicontrol('Style', 'text', 'Position', [700,10,200,30], ...
    'String', '摄像头状态: 未锁定', 'FontSize', 10);

% 创建控制按钮
uicontrol(btnStyle{:}, 'String','锁定摄像头1',...
    'Position',[100,10,150,30], 'Callback',@(s,e)LockTarget(1));
uicontrol(btnStyle{:}, 'String','锁定摄像头2',...
    'Position',[300,10,150,30], 'Callback',@(s,e)LockTarget(2));


% 创建清理对象
cleanupObj = onCleanup(@() closeApp(Fig, []));

%% ======================== 主循环 ==========================
    try
        while ishandle(Fig)
            for camIdx = 1:2
                if isempty(cams(camIdx).Hobj), continue; end
                
                %% ------------------- 帧采集 -------------------
                try
                    rawFrame = getsnapshot(cams(camIdx).Hobj);
                    
                    % 格式转换修正
                    if strcmpi(cams(camIdx).Hobj.ReturnedColorSpace, 'ycbcr')
                        rgbFrame = ycbcr2rgb(rawFrame);
                    elseif strcmpi(cams(camIdx).Hobj.ReturnedColorSpace, 'rgb')
                        rgbFrame = rawFrame;
                    else
                        rgbFrame = rawFrame; % 默认不转换
                    end
                    
                    % 确保uint8类型
                    if ~isa(rgbFrame, 'uint8')
                        rgbFrame = uint8(rgbFrame * 255);
                    end
                    
                    % 存储当前帧
                    cams(camIdx).frame = rgbFrame;
                    
                    % 显示实时画面
                    imshow(rgbFrame, 'Parent', cams(camIdx).axes(1));
                    
                    %% ------------------- 目标跟踪 -------------------
                    if cams(camIdx).flag
                        processFrame = im2double(rgbFrame);
                        grayFrame = rgb2gray(processFrame);
                        
                        % 添加图像预处理
                        grayFrame = imadjust(grayFrame);         % 增强对比度
                        grayFrame = imgaussfilt(grayFrame, 0.5); % 轻微平滑降噪
                        
                        % 特征点跟踪
                        [points, validity] = cams(camIdx).tracker(grayFrame);
                        validPoints = points(validity,:);
                        
                        % 特征点不足时重置
                        if size(validPoints,1) < min_features
                            release(cams(camIdx).tracker);
                            if ~isempty(cams(camIdx).points)
                                initialize(cams(camIdx).tracker,...
                                    cams(camIdx).points.Location, grayFrame);
                                [points, validity] = cams(camIdx).tracker(grayFrame);
                                validPoints = points(validity,:);
                            end
                        end
                        
                        % 标记特征点
                        if ~isempty(validPoints)
                            markedFrame = insertMarker(processFrame, validPoints, '+', 'Color','green');
                            imshow(markedFrame, 'Parent', cams(camIdx).axes(1));
                        end
                    end
                catch ME
                    warning('摄像头%d帧获取失败: %s', camIdx, ME.message);
                end
            end

            % 实时特征匹配（当两个摄像头都处于跟踪状态时）
            % 修改特征匹配部分代码
if cams(1).flag && cams(2).flag
    try
        % 对当前帧提取特征
        for camIdx = 1:2
            grayFrame = rgb2gray(im2double(cams(camIdx).frame));
            grayFrame = imadjust(grayFrame);
            grayFrame = imgaussfilt(grayFrame, 0.5);
            
            if ~isempty(cams(camIdx).points)
                % 对已有特征点进行追踪
                [points, validity] = cams(camIdx).tracker(grayFrame);
                validPoints = points(validity,:);
                
                % 特征点不足时在原始ROI区域重新检测
                if size(validPoints,1) < min_features
                    validPoints = cams(camIdx).points.Location;
                    padding = 40;
                    roi = [min(validPoints(:,1))-padding, min(validPoints(:,2))-padding, ...
                           max(validPoints(:,1))-min(validPoints(:,1))+2*padding, ...
                           max(validPoints(:,2))-min(validPoints(:,2))+2*padding];
                    roiImage = imcrop(grayFrame, roi);
                    
                    points = detectFASTFeatures(roiImage, 'MinContrast', 0.05, 'MinQuality', 0.05);
                    points = points.selectStrongest(300);
                    [features, points] = extractFeatures(roiImage, points, 'Method', 'FREAK');
                    points.Location = points.Location + [roi(1), roi(2)];
                    
                    % 重新初始化追踪器
                    release(cams(camIdx).tracker);
                    initialize(cams(camIdx).tracker, points.Location, grayFrame);
                    [points, validity] = cams(camIdx).tracker(grayFrame);
                    validPoints = points(validity,:);
                end
                
                cams(camIdx).currentPoints = cornerPoints(validPoints);
                [cams(camIdx).currentFeatures, cams(camIdx).currentPoints] = ...
                    extractFeatures(grayFrame, cams(camIdx).currentPoints, 'Method', 'FREAK');
            end
        end
        
       
                    
                            % 如果两个摄像头都有有效特征点
                            if ~isempty(cams(1).currentPoints) && ~isempty(cams(2).currentPoints)
                                % 执行特征匹配
                                indexPairs = matchFeatures(cams(1).currentFeatures, cams(2).currentFeatures, ...
                                    'MatchThreshold', 90, ...
                                    'MaxRatio', 0.9, ...
                                    'Unique', true);
                                
                                matchedPoints1 = cams(1).currentPoints(indexPairs(:,1));
                                matchedPoints2 = cams(2).currentPoints(indexPairs(:,2));
                                
                                % 在计算视差的同时计算深度
                                if ~isempty(matchedPoints1) && ~isempty(matchedPoints2)
                                    % 初始化视差数组
                                    numPoints = size(matchedPoints1.Location, 1);
                                    disparities_x = zeros(numPoints, 1);
                                    disparities_y = zeros(numPoints, 1);
                                    disparities_total = zeros(numPoints, 1);
                                    
                                    % fprintf('\n====== 原始视差信息（未过滤） ======\n');
                                    
                                    % 计算原始视差信息
                                    for i = 1:numPoints
                                        % 计算视差分量（保留符号）
                                        disparities_x(i) = matchedPoints1.Location(i,1) - matchedPoints2.Location(i,1);
                                        disparities_y(i) = matchedPoints1.Location(i,2) - matchedPoints2.Location(i,2);
                                        % 计算总视差（几何距离）
                                        disparities_total(i) = sqrt(disparities_x(i)^2 + disparities_y(i)^2);
                                        
                                        % 显示原始视差数据
                                        fprintf('点对 %3d: 水平视差 = %6.2f, 垂直视差 = %6.2f, 总视差 = %6.2f\n',...
                                            i, disparities_x(i), disparities_y(i), disparities_total(i));
                                    end
                                    
                                    % 显示原始视差统计信息
                                    fprintf('\n原始视差统计:\n');
                                    fprintf('总点数: %d\n', numPoints);
                                    fprintf('水平视差 - 平均值: %.2f, 标准差: %.2f\n', mean(disparities_x), std(disparities_x));
                                    fprintf('垂直视差 - 平均值: %.2f, 标准差: %.2f\n', mean(disparities_y), std(disparities_y));
                                    fprintf('========================\n\n');
                                    
                                    % 基于视差的过滤
                                    mean_x = mean(disparities_x);
                                    std_x = std(disparities_x);
                                    mean_y = mean(disparities_y);
                                    std_y = std(disparities_y);
                                    
                                    validIdx_x = abs(disparities_x - mean_x) <= 0.6*std_x;
                                    validIdx_y = abs(disparities_y - mean_y) <= 0.6*std_y;
                                    
                                    max_abs_disparity_x = 70;
                                    max_abs_disparity_y = 30;
                                    
                                    validIdx_abs_x = abs(disparities_x) <= max_abs_disparity_x;
                                    validIdx_abs_y = abs(disparities_y) <= max_abs_disparity_y;
                                    
                                    % 组合视差过滤条件
                                    validIdx = validIdx_x & validIdx_y & validIdx_abs_x & validIdx_abs_y;
                                    
                                    % 获取视差过滤后的有效点
                                    validPoints1 = matchedPoints1(validIdx);
                                    validPoints2 = matchedPoints2(validIdx);
                                    validDisparities_x = disparities_x(validIdx);
                                    validDisparities_y = disparities_y(validIdx);
                                    validDisparities_total = disparities_total(validIdx);
                                    
                                    % % 显示视差过滤后的信息
                                    % fprintf('====== 视差过滤后的信息 ======\n');
                                    % for i = 1:sum(validIdx)
                                    %     fprintf('有效点 %3d: 水平视差 = %6.2f, 垂直视差 = %6.2f, 总视差 = %6.2f\n',...
                                    %         i, validDisparities_x(i), validDisparities_y(i), validDisparities_total(i));
                                    % end
                                    % 
                                    % % 显示视差过滤后的统计
                                    % fprintf('\n视差过滤后统计:\n');
                                    % fprintf('视差过滤后剩余点数: %d\n', sum(validIdx));
                                    % fprintf('水平视差 - 平均值: %.2f, 标准差: %.2f\n', ...
                                    %     mean(validDisparities_x), std(validDisparities_x));
                                    % fprintf('垂直视差 - 平均值: %.2f, 标准差: %.2f\n', ...
                                    %     mean(validDisparities_y), std(validDisparities_y));
                                    % fprintf('========================\n\n');
                                    
                                % 特征点连线的可视化
                                showMatchedFeatures(cams(1).frame, cams(2).frame,...
                                    validPoints1, validPoints2, 'montage',...
                                    'Parent', cams(1).axes(2));
                                
                                % title(cams(1).axes(2), sprintf('视差过滤后的匹配点对: %d\n水平视差: %.2f±%.2f\n垂直视差: %.2f±%.2f',...
                                    % sum(validIdx), mean(validDisparities_x), std(validDisparities_x),...
                                    % mean(validDisparities_y), std(validDisparities_y)));
                                
                                
                                    % 获取相机参数并计算深度
                                    baseline = norm(cameraParams.T);    % 单位：mm
                                    focal_length = cameraParams.K1(1,1); % 单位：mm
                                    
                                    % 对视差过滤后的点计算深度
                                    validDepths = zeros(sum(validIdx), 1);
                                    % fprintf('====== 视差过滤后点的深度信息 ======\n');
                                    for i = 1:sum(validIdx)
                                        % 使用视差的绝对值计算深度
                                        disparity_abs = abs(validDisparities_x(i));
                                        if disparity_abs > 0  % 避免除以零
                                            validDepths(i) = (baseline * focal_length) / disparity_abs;
                                            % fprintf('点 %3d: 水平视差 = %6.2f, 垂直视差 = %6.2f, 总视差 = %6.2f, 深度 = %8.2f mm\n',...
                                                % i, validDisparities_x(i), validDisparities_y(i), ...
                                                % validDisparities_total(i), validDepths(i));
                                        else
                                            validDepths(i) = nan;
                                            % fprintf('点 %3d: 水平视差 = %6.2f, 垂直视差 = %6.2f, 总视差 = %6.2f, 深度 = 无效\n',...
                                                % i, validDisparities_x(i), validDisparities_y(i), validDisparities_total(i));
                                        end
                                    end
                                    
                                    % 基于深度的过滤
                                    mean_depth = mean(validDepths, 'omitnan');
                                    std_depth = std(validDepths, 'omitnan');
                                    
                                    validIdx_depth = abs(validDepths - mean_depth) <= 0.6*std_depth & ...
                                                    validDepths >= 100 & validDepths <= 2000 & ...
                                                    ~isnan(validDepths);  % 确保排除NaN值
                                    
                                    % [后面的代码保持不变]
                                    
                                    % 应用深度过滤
                                    final_points1 = validPoints1(validIdx_depth);
                                    final_points2 = validPoints2(validIdx_depth);
                                    final_disparities_x = validDisparities_x(validIdx_depth);
                                    final_disparities_y = validDisparities_y(validIdx_depth);
                                    final_disparities_total = validDisparities_total(validIdx_depth);
                                    final_depths = validDepths(validIdx_depth);
                                    
                                    % 显示最终过滤后的信息
                                    fprintf('\n====== 深度过滤后的最终信息 ======\n');
                                    for i = 1:sum(validIdx_depth)
                                        fprintf('最终点 %3d: 水平视差 = %6.2f, 垂直视差 = %6.2f, 总视差 = %6.2f, 深度 = %8.2f mm\n',...
                                            i, final_disparities_x(i), final_disparities_y(i), ...
                                            final_disparities_total(i), final_depths(i));
                                    end
                                    
                                    % 显示最终统计信息
                                    fprintf('\n最终统计信息:\n');
                                    fprintf('深度过滤后最终点数: %d\n', sum(validIdx_depth));
                                    fprintf('水平视差 - 平均值: %.2f, 标准差: %.2f\n', ...
                                        mean(final_disparities_x), std(final_disparities_x));
                                    fprintf('垂直视差 - 平均值: %.2f, 标准差: %.2f\n', ...
                                        mean(final_disparities_y), std(final_disparities_y));
                                    fprintf('深度 - 平均值: %.2f, 标准差: %.2f, 最小值: %.2f, 最大值: %.2f mm\n',...
                                        mean(final_depths), std(final_depths), min(final_depths), max(final_depths));
                                    fprintf('========================\n\n');

                                    % 在这里添加3D可视化更新
                                    points3D = [final_points1.Location, final_depths];
                                    vis = updateVisualization(vis, points3D);
                                    
                                    % 显示最终匹配结果
                                    showMatchedFeatures(cams(1).frame, cams(2).frame,...
                                        final_points1, final_points2, 'montage',...
                                        'Parent', cams(1).axes(2));
                                    
                                    title(cams(1).axes(2), sprintf('有效匹配点对: %d\n水平视差: %.2f±%.2f\n垂直视差: %.2f±%.2f\n平均深度: %.2f±%.2f mm',...
                                        sum(validIdx_depth), mean(final_disparities_x), std(final_disparities_x),...
                                        mean(final_disparities_y), std(final_disparities_y),...
                                        mean(final_depths), std(final_depths)));
                                end
                            end
                        catch ME
                            warning(ME.identifier,'特征匹配失败: %s', ME.message);
                        end
                    end        
            drawnow limitrate;
        end
    catch ME
        errordlg(['运行错误: ' ME.message]);
        closeApp(Fig, []);
    end
    
    %% ====================== 加载相机参数函数 ======================
    % 在主函数开始处添加，全局参数初始化之后
    function cameraParams = loadCameraParams()
        try
            % 加载标定参数文件
            stereoParams = load('stereoParams.mat');
            
            % 获取重要的标定参数
            cameraParams1 = stereoParams.stereoParams.CameraParameters1;
            cameraParams2 = stereoParams.stereoParams.CameraParameters2;
            
            % 创建结构体存储参数
            cameraParams.K1 = cameraParams1.IntrinsicMatrix';
            cameraParams.K2 = cameraParams2.IntrinsicMatrix';
            cameraParams.D1 = cameraParams1.RadialDistortion;
            cameraParams.D2 = cameraParams2.RadialDistortion;
            cameraParams.R = stereoParams.stereoParams.RotationOfCamera2';
            cameraParams.T = stereoParams.stereoParams.TranslationOfCamera2;
            
            fprintf('相机参数加载成功\n');
        catch ME
            warning(ME.identifier, '相机参数加载失败: %s', ME.message);
            cameraParams = struct('K1',[],'K2',[],'D1',[],'D2',[],'R',[],'T',[]);
        end
    end
    %% ====================== 资源清理函数 ========================
    function closeApp(~,~)
        % 分步释放摄像头资源
        for idx = 1:numel(cams)
            if ~isempty(cams(idx).Hobj) && isvalid(cams(idx).Hobj)
                try
                    % 关闭预览
                    if ispreviewing(cams(idx).Hobj)
                        closepreview(cams(idx).Hobj);
                    end
                    
                    % 停止并删除对象
                    stop(cams(idx).Hobj);
                    delete(cams(idx).Hobj);
                catch ME
                    warning('摄像头%d释放失败: %s', idx, ME.message);
                end
            end
        end
        
        % 强制清除残留
        imaqreset; 
        
        % 关闭窗口
        delete(Fig);
    end

    %% ====================== 目标锁定回调 ========================
    function LockTarget(camIdx)

        if isempty(cams(camIdx).Hobj)
            errordlg(sprintf('摄像头%d未正确初始化', camIdx));
            return;
        end
        
        try
            % 获取初始帧
            rawFrame = getsnapshot(cams(camIdx).Hobj);
            if strcmpi(cams(camIdx).Hobj.ReturnedColorSpace, 'ycbcr')
                rgbFrame = ycbcr2rgb(rawFrame);
            else
                rgbFrame = rawFrame;
            end
            processFrame = im2double(rgbFrame);
            
            % 显示选择画面
            imshow(processFrame, 'Parent', cams(camIdx).axes(1));
            
            % ROI选择
            [x,y] = ginput(2);
            
            % 输入有效性检查
            if numel(x) < 2 || numel(y) < 2
                errordlg('必须选择两个点来定义区域。');
                cams(camIdx).flag = 0;
                return;
            end
            
            % 在 LockTarget 函数中直接修改为：
            x = min(max(x, 1), cams(camIdx).imgSize(1));
            y = min(max(y, 1), cams(camIdx).imgSize(2));
            roi = round([min(x), min(y), max(x)-min(x), max(y)-min(y)]);
            
            % 特征检测和描述子提取
            grayFrame = rgb2gray(processFrame);
            roiImage = imcrop(grayFrame, roi);

            % 添加图像预处理
            roiImage = imadjust(roiImage, [0.3 0.7], [0 1]);  % 增强对比度
            roiImage = imgaussfilt(roiImage, 0.5); % 轻微平滑降噪

            
            % 使用FAST特征检测器
            points = detectFASTFeatures(roiImage, 'MinContrast', 0.1, 'MinQuality', 0.1);
            % 选择最强的特征点（数量更多）
            points = points.selectStrongest(200);
            [features, validPoints] = extractFeatures(roiImage, points, 'Method', 'FREAK');
            
            % 更新点的坐标到原始图像空间
            validPoints.Location = validPoints.Location + [roi(1), roi(2)];
            
            % 存储特征点和描述子
            cams(camIdx).points = validPoints;
            cams(camIdx).descriptors = features;
            
            % 特征点数量检查
            if isempty(validPoints)
                error('未检测到有效特征点（建议选择纹理丰富的区域）');
            end
            
            % 显示特征点
            featureFrame = insertMarker(processFrame, validPoints.Location, '+','Color','green');
            imshow(featureFrame, 'Parent', cams(camIdx).axes(2));
            
            % 初始化跟踪器
            release(cams(camIdx).tracker);
            initialize(cams(camIdx).tracker, validPoints.Location, grayFrame);
            cams(camIdx).flag = 1;
            fprintf('摄像头%d已成功锁定\n', camIdx);
            fprintf('当前状态 - 摄像头1: %d, 摄像头2: %d\n', cams(1).flag, cams(2).flag);
            updateStatusDisplay();

        catch ME
        cams(camIdx).flag = 0;
        errordlg(sprintf('摄像头%d锁定失败: %s', camIdx, ME.message));
        fprintf('摄像头%d锁定失败\n', camIdx);
        updateStatusDisplay();
    end
end
    



%% ====================== 状态更新函数 ========================
    function updateStatusDisplay()

        if cams(1).flag && cams(2).flag
            set(statusText, 'String', '摄像头状态: 全部锁定');
        elseif cams(1).flag
            set(statusText, 'String', '摄像头状态: 仅摄像头1锁定');
        elseif cams(2).flag
            set(statusText, 'String', '摄像头状态: 仅摄像头2锁定');
        else
            set(statusText, 'String', '摄像头状态: 未锁定');
        end
        drawnow;  % 强制更新显示
    end

%% ====================== 3D可视化相关函数 ======================
    function vis = initializeVisualization()
    vis = struct();
    vis.Fig3D = [];
    vis.Axes3D = [];
    vis.historyPolygons = cell(1, 10);  % 存储10帧历史
    vis.currentIdx = 1;
    vis.isInitialized = false;
end

function vis = updateVisualization(vis, points3D)
    vis = setupVisualization(vis);
    
    if ~isempty(points3D)
        % 存储新的多边形数据
        vis.historyPolygons{vis.currentIdx} = points3D;
        
        % 清除所有现有多边形
        cla(vis.Axes3D);
        
        % 显示历史多边形
        for i = 1:10
            idx = mod(vis.currentIdx - i + 9, 10) + 1;
            if ~isempty(vis.historyPolygons{idx})
                points = vis.historyPolygons{idx};
                % 按角度排序
                center = mean(points(:,1:2));
                angles = atan2(points(:,2) - center(2), points(:,1) - center(1));
                [~, sortIdx] = sort(angles);
                ordered_points = points(sortIdx,:);
                
                % 绘制多边形，透明度随时间衰减
                alpha = max(0.1, 1 - i/10);
                fill3(vis.Axes3D, ...
                    ordered_points(:,1), ...
                    ordered_points(:,2), ...
                    ones(size(ordered_points,1),1) * mean(ordered_points(:,3)), ...
                    [0.3 0.6 0.9], ...
                    'FaceAlpha', alpha, ...
                    'EdgeColor', 'blue');
            end
        end
        
        vis.currentIdx = mod(vis.currentIdx, 10) + 1;
        drawnow limitrate;
    end
end

function vis = setupVisualization(vis)
    if isempty(vis.Fig3D) || ~isvalid(vis.Fig3D)
        vis.Fig3D = figure('Name', '3D运动轨迹');
        vis.Axes3D = axes('Parent', vis.Fig3D);
        
        grid(vis.Axes3D, 'on');
        hold(vis.Axes3D, 'on');
        xlabel(vis.Axes3D, 'X (pixels)');
        ylabel(vis.Axes3D, 'Y (pixels)');
        zlabel(vis.Axes3D, 'Z (mm)');
        view(vis.Axes3D, 45, 30);
        
        % 固定坐标轴范围
        axis(vis.Axes3D, [400 1200 300 1000 200 1000]);
        
        rotate3d(vis.Axes3D, 'on');
        vis.polygon = [];
    end
end

    % 计算点的质心
    centroid1 = mean(points1, 1);
    centroid2 = mean(points2, 1);

    % 相对于质心的角度排序
    angles1 = atan2(points1(:,2) - centroid1(2), points1(:,1) - centroid1(1));
    angles2 = atan2(points2(:,2) - centroid2(2), points2(:,1) - centroid2(1));
    
    [~, idx1] = sort(angles1);
    [~, idx2] = sort(angles2);
    
    points1 = points1(idx1,:);
    points2 = points2(idx2,:);

    % 重采样到固定数量的点（比如20个点）
    num_samples = 20;
    
    % 对第一帧重采样
    if size(points1, 1) > 1
        points1_resampled = resamplePoints(points1, num_samples);
    else
        points1_resampled = repmat(points1, num_samples, 1);
    end
    
    % 对第二帧重采样
    if size(points2, 1) > 1
        points2_resampled = resamplePoints(points2, num_samples);
    else
        points2_resampled = repmat(points2, num_samples, 1);
    end

    % 创建网格点
    x = [points1_resampled(:,1)'; points2_resampled(:,1)'];
    y = [points1_resampled(:,2)'; points2_resampled(:,2)'];
    z = [points1_resampled(:,3)'; points2_resampled(:,3)'];
    
    % 计算透明度（越早的帧越透明）
    alpha = max(0.1, 1 - frameIdx/10);
    
    % 创建surface对象，添加光滑效果
    surfaceObj = surf(ax, x, y, z, ...
        'FaceColor', [0.3 0.6 0.9], ...
        'EdgeColor', 'interp', ...
        'FaceAlpha', alpha, ...
        'FaceLighting', 'gouraud', ...
        'EdgeLighting', 'gouraud');
end

function points_resampled = resamplePoints(points, num_samples)
    % 计算原始点之间的累积距离
    dists = [0; cumsum(sqrt(sum(diff(points).^2, 2)))];
    total_dist = dists(end);
    
    % 创建均匀分布的新距离点
    new_dists = linspace(0, total_dist, num_samples)';
    
    % 对每个维度进行插值
    points_resampled = zeros(num_samples, size(points, 2));
    for dim = 1:size(points, 2)
        points_resampled(:,dim) = interp1(dists, points(:,dim), new_dists, 'pchip');
    end
end
